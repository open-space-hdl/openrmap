---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Memory access of the RMAP target (TG-4): executes write and read commands of any byte address
-- and length on the AXI4 master olo_ft_axi_master_full. A single-address command is split into one
-- AXI command per memory word, all at the same address. Busy covers the commands not yet completed
-- on AXI; Err is set by an AXI error response or a double error in a data buffer of the master and
-- stays set until ErrClr. The bytes of a command are packed into AXI words (first byte in the least
-- significant byte) here and the master runs with the AXI data width on its user side.
--
-- Documentation: hdl/orm_tgt/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_tgt_mem is
    generic (
        AxiAddrWidth_g : positive range 12 to 40 := 32;
        AxiDataWidth_g : positive                := 32;
        AxiMaxBeats_g  : positive range 1 to 256 := 16
    );
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Commands
        Cmd_Valid     : in    std_logic;
        Cmd_Ready     : out   std_logic;
        Cmd_Write     : in    std_logic;
        Cmd_Addr      : in    std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        Cmd_Size      : in    std_logic_vector(23 downto 0); -- Bytes, at least 1
        Cmd_Single    : in    std_logic;                     -- Every memory word at Cmd_Addr
        -- Data
        Wr_Data       : in    std_logic_vector(7 downto 0);
        Wr_Valid      : in    std_logic;
        Wr_Ready      : out   std_logic;
        Rd_Data       : out   std_logic_vector(7 downto 0);
        Rd_Valid      : out   std_logic;
        Rd_Ready      : in    std_logic;
        -- Status
        Busy          : out   std_logic;
        Err           : out   std_logic;
        ErrClr        : in    std_logic;
        -- ECC events and error injection of the data buffers of the master
        Ecc_WrSec     : out   std_logic;
        Ecc_WrDed     : out   std_logic;
        Ecc_RdSec     : out   std_logic;
        Ecc_RdDed     : out   std_logic;
        WrInj_BitFlip : in    std_logic_vector(eccCodewordWidth(AxiDataWidth_g) - 1 downto 0)     := (others => '0');
        WrInj_Valid   : in    std_logic                                                           := '0';
        RdInj_BitFlip : in    std_logic_vector(eccCodewordWidth(AxiDataWidth_g + 1) - 1 downto 0) := (others => '0');
        RdInj_Valid   : in    std_logic                                                           := '0';
        -- AXI4 master
        M_Axi_AwAddr  : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_AwLen   : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize  : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock  : out   std_logic;
        M_Axi_AwCache : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt  : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid : out   std_logic;
        M_Axi_AwReady : in    std_logic;
        M_Axi_WData   : out   std_logic_vector(AxiDataWidth_g - 1 downto 0);
        M_Axi_WStrb   : out   std_logic_vector(AxiDataWidth_g / 8 - 1 downto 0);
        M_Axi_WLast   : out   std_logic;
        M_Axi_WValid  : out   std_logic;
        M_Axi_WReady  : in    std_logic;
        M_Axi_BResp   : in    std_logic_vector(1 downto 0);
        M_Axi_BValid  : in    std_logic;
        M_Axi_BReady  : out   std_logic;
        M_Axi_ArAddr  : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_ArLen   : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize  : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock  : out   std_logic;
        M_Axi_ArCache : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt  : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid : out   std_logic;
        M_Axi_ArReady : in    std_logic;
        M_Axi_RData   : in    std_logic_vector(AxiDataWidth_g - 1 downto 0);
        M_Axi_RResp   : in    std_logic_vector(1 downto 0);
        M_Axi_RLast   : in    std_logic;
        M_Axi_RValid  : in    std_logic;
        M_Axi_RReady  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_tgt_mem is

    constant WordBytes_c : positive := AxiDataWidth_g / 8;
    constant SizeBits_c  : positive := minimum(24, AxiAddrWidth_g);
    -- Data buffers of the master: two bursts of AxiMaxBeats_g words
    constant FifoWords_c : positive := 2 ** log2ceil(2 * AxiMaxBeats_g);

    type Fsm_t is (Idle_s, Issue_s);

    type TwoProcess_r is record
        Fsm      : Fsm_t;
        Write    : std_logic;
        Addr     : std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        Size     : std_logic_vector(23 downto 0);
        Words    : unsigned(23 downto 0); -- Remaining AXI commands of a single-address command
        OpenCnt  : natural range 0 to 1023;
        Err      : std_logic;
        -- Packing of the write bytes, unpacking of the read words
        WrRemain : unsigned(23 downto 0);
        WrWord   : std_logic_vector(AxiDataWidth_g - 1 downto 0);
        WrIdx    : natural range 0 to AxiDataWidth_g / 8;
        WrValid  : std_logic;
        RdRemain : unsigned(23 downto 0);
        RdIdx    : natural range 0 to AxiDataWidth_g / 8 - 1;
    end record;

    signal r, r_next : TwoProcess_r;

    signal CmdWrValid : std_logic;
    signal CmdWrReady : std_logic;
    signal CmdRdValid : std_logic;
    signal CmdRdReady : std_logic;
    signal CmdSize    : std_logic_vector(SizeBits_c - 1 downto 0);
    signal WrDone     : std_logic;
    signal WrError    : std_logic;
    signal RdDone     : std_logic;
    signal RdError    : std_logic;
    signal RdValid_i  : std_logic;
    signal RdEccDed   : std_logic;
    signal WrEccDed   : std_logic;
    signal RdEccSec   : std_logic;
    signal MWrReady   : std_logic;
    signal MRdData    : std_logic_vector(AxiDataWidth_g - 1 downto 0);
    signal MRdReady   : std_logic;
    signal RReady_i   : std_logic;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Issue_v : boolean;
        variable Open_v  : integer range -2 to 1024;
    begin
        v := r;

        -- Command to the master
        Issue_v := false;
        if r.Fsm = Issue_s then
            if (r.Write = '1' and CmdWrReady = '1') or (r.Write = '0' and CmdRdReady = '1') then
                Issue_v := true;
                if r.Words > 1 then
                    v.Words := r.Words - 1;
                else
                    v.Fsm := Idle_s;
                end if;
            end if;
        end if;

        if r.Fsm = Idle_s and Cmd_Valid = '1' and r.WrRemain = 0 and r.RdRemain = 0 then
            v.Fsm := Issue_s;
            if Cmd_Write = '1' then
                v.WrRemain := unsigned(Cmd_Size);
                v.WrIdx    := 0;
            else
                v.RdRemain := unsigned(Cmd_Size);
                v.RdIdx    := 0;
            end if;
            v.Write := Cmd_Write;
            v.Addr  := Cmd_Addr;
            if Cmd_Single = '1' then
                v.Size  := std_logic_vector(to_unsigned(WordBytes_c, 24));
                v.Words := unsigned(Cmd_Size) / WordBytes_c;
            else
                v.Size  := Cmd_Size;
                v.Words := to_unsigned(1, 24);
            end if;
        end if;

        -- Commands open on AXI: one more per command issued, one less per completion of each direction
        Open_v := r.OpenCnt;
        if Issue_v then
            Open_v := Open_v + 1;
        end if;
        if WrDone = '1' or WrError = '1' then
            Open_v := Open_v - 1;
        end if;
        if RdDone = '1' or RdError = '1' then
            Open_v := Open_v - 1;
        end if;
        v.OpenCnt := maximum(0, minimum(1023, Open_v));

        -- ECSS 5.3.3.10, 5.4.3.10: memory errors. The response of every read beat is checked here, because the
        -- master reports only the response of the last beat of a burst.
        if ErrClr = '1' then
            v.Err := '0';
        end if;
        if WrError = '1' or RdError = '1' or WrEccDed = '1' or (RdEccDed = '1' and RdValid_i = '1' and MRdReady = '1') or
           (M_Axi_RValid = '1' and RReady_i = '1' and M_Axi_RResp(1) = '1') then
            v.Err := '1';
        end if;

        CmdWrValid <= '1' when r.Fsm = Issue_s and r.Write = '1' else '0';
        CmdRdValid <= '1' when r.Fsm = Issue_s and r.Write = '0' else '0';
        Cmd_Ready  <= '1' when r.Fsm = Idle_s and r.WrRemain = 0 and r.RdRemain = 0 else '0';

        -- Write bytes packed into words: a word is complete after its last byte or the last byte of the command
        if r.WrValid = '1' and MWrReady = '1' then
            v.WrValid := '0';
        end if;
        Wr_Ready <= '1' when r.WrRemain /= 0 and (r.WrValid = '0' or MWrReady = '1') else '0';
        if Wr_Valid = '1' and r.WrRemain /= 0 and (r.WrValid = '0' or MWrReady = '1') then
            v.WrWord(8 * r.WrIdx + 7 downto 8 * r.WrIdx) := Wr_Data;
            v.WrRemain                                   := r.WrRemain - 1;
            if r.WrIdx = WordBytes_c - 1 or r.WrRemain = 1 then
                v.WrValid := '1';
                v.WrIdx   := 0;
            else
                v.WrIdx := r.WrIdx + 1;
            end if;
        end if;

        -- Read words unpacked into bytes: the last word of a command holds the remaining bytes
        Rd_Valid <= RdValid_i when r.RdRemain /= 0 else '0';
        Rd_Data  <= MRdData(8 * r.RdIdx + 7 downto 8 * r.RdIdx);
        MRdReady <= '0';
        if RdValid_i = '1' and r.RdRemain /= 0 and Rd_Ready = '1' then
            v.RdRemain := r.RdRemain - 1;
            if r.RdIdx = WordBytes_c - 1 or r.RdRemain = 1 then
                MRdReady <= '1';
                v.RdIdx  := 0;
            else
                v.RdIdx := r.RdIdx + 1;
            end if;
        end if;

        r_next <= v;
    end process;

    CmdSize      <= r.Size(SizeBits_c - 1 downto 0);
    Busy         <= '1' when r.Fsm /= Idle_s or r.OpenCnt /= 0 or r.WrRemain /= 0 or r.WrValid = '1' else '0';
    Err          <= r.Err;
    Ecc_WrDed    <= WrEccDed;
    M_Axi_RReady <= RReady_i;
    Ecc_RdSec    <= RdEccSec and RdValid_i and MRdReady;
    Ecc_RdDed    <= RdEccDed and RdValid_i and MRdReady;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm      <= Idle_s;
                r.OpenCnt  <= 0;
                r.Err      <= '0';
                r.WrRemain <= (others => '0');
                r.WrValid  <= '0';
                r.RdRemain <= (others => '0');
            end if;
        end if;
    end process;

    i_master : entity olo.olo_ft_axi_master_full
        generic map (
            AxiAddrWidth_g            => AxiAddrWidth_g,
            AxiDataWidth_g            => AxiDataWidth_g,
            AxiMaxBeats_g             => AxiMaxBeats_g,
            AxiMaxOpenTransactions_g  => 4,
            UserTransactionSizeBits_g => SizeBits_c,
            DataFifoDepth_g           => FifoWords_c,
            UserDataWidth_g           => AxiDataWidth_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            CmdWr_Addr        => r.Addr,
            CmdWr_Size        => CmdSize,
            CmdWr_Valid       => CmdWrValid,
            CmdWr_Ready       => CmdWrReady,
            CmdRd_Addr        => r.Addr,
            CmdRd_Size        => CmdSize,
            CmdRd_Valid       => CmdRdValid,
            CmdRd_Ready       => CmdRdReady,
            Wr_Data           => r.WrWord,
            Wr_Valid          => r.WrValid,
            Wr_Ready          => MWrReady,
            Wr_EccSec         => Ecc_WrSec,
            Wr_EccDed         => WrEccDed,
            Rd_Data           => MRdData,
            Rd_Last           => open,
            Rd_Valid          => RdValid_i,
            Rd_Ready          => MRdReady,
            Rd_EccSec         => RdEccSec,
            Rd_EccDed         => RdEccDed,
            Wr_Done           => WrDone,
            Wr_Error          => WrError,
            Rd_Done           => RdDone,
            Rd_Error          => RdError,
            Wr_ErrInj_BitFlip => WrInj_BitFlip,
            Wr_ErrInj_Valid   => WrInj_Valid,
            Rd_ErrInj_BitFlip => RdInj_BitFlip,
            Rd_ErrInj_Valid   => RdInj_Valid,
            M_Axi_AwAddr      => M_Axi_AwAddr,
            M_Axi_AwLen       => M_Axi_AwLen,
            M_Axi_AwSize      => M_Axi_AwSize,
            M_Axi_AwBurst     => M_Axi_AwBurst,
            M_Axi_AwLock      => M_Axi_AwLock,
            M_Axi_AwCache     => M_Axi_AwCache,
            M_Axi_AwProt      => M_Axi_AwProt,
            M_Axi_AwValid     => M_Axi_AwValid,
            M_Axi_AwReady     => M_Axi_AwReady,
            M_Axi_WData       => M_Axi_WData,
            M_Axi_WStrb       => M_Axi_WStrb,
            M_Axi_WLast       => M_Axi_WLast,
            M_Axi_WValid      => M_Axi_WValid,
            M_Axi_WReady      => M_Axi_WReady,
            M_Axi_BResp       => M_Axi_BResp,
            M_Axi_BValid      => M_Axi_BValid,
            M_Axi_BReady      => M_Axi_BReady,
            M_Axi_ArAddr      => M_Axi_ArAddr,
            M_Axi_ArLen       => M_Axi_ArLen,
            M_Axi_ArSize      => M_Axi_ArSize,
            M_Axi_ArBurst     => M_Axi_ArBurst,
            M_Axi_ArLock      => M_Axi_ArLock,
            M_Axi_ArCache     => M_Axi_ArCache,
            M_Axi_ArProt      => M_Axi_ArProt,
            M_Axi_ArValid     => M_Axi_ArValid,
            M_Axi_ArReady     => M_Axi_ArReady,
            M_Axi_RData       => M_Axi_RData,
            M_Axi_RResp       => M_Axi_RResp,
            M_Axi_RLast       => M_Axi_RLast,
            M_Axi_RValid      => M_Axi_RValid,
            M_Axi_RReady      => RReady_i
        );

end architecture;
