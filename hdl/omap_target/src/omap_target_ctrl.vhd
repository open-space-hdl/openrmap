---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Command controller of the RMAP Target (TG-3): sequence of one command from the decoded header to
-- the reply. It starts the authorisation, asks the external authorisation port, buffers write data
-- in an FT FIFO (verified writes completely, non-verified writes in chunks committed to memory as
-- they complete), executes reads and read-modify-writes on the memory access block, determines the
-- status in the priority of architecture decision D9 and requests the reply.
--
-- Documentation: hdl/omap_target/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.omap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_target_ctrl is
    generic (
        AxiAddrWidth_g : positive range 12 to 40 := 32;
        AxiDataWidth_g : positive                := 32;
        BufferBytes_g  : positive                := 256;
        ChunkBytes_g   : positive                := 32;
        ExtAuth_g      : boolean                 := false
    );
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Decoder
        Hdr_Valid      : in    std_logic;
        Hdr_Ready      : out   std_logic;
        Hdr            : in    CmdHeader_t;
        Data_Valid     : in    std_logic;
        Data_Ready     : out   std_logic;
        Data_Byte      : in    std_logic_vector(7 downto 0);
        End_Valid      : in    std_logic;
        End_Ready      : out   std_logic;
        End_Eep        : in    std_logic;
        End_Immediate  : in    std_logic;
        End_Early      : in    std_logic;
        End_Excess     : in    std_logic;
        End_CrcOk      : in    std_logic;
        -- Authorisation
        Auth_Start     : out   std_logic;
        Auth_Hdr       : out   CmdHeader_t;
        Auth_Done      : in    std_logic;
        Auth_Discard   : in    std_logic;
        Auth_Status    : in    std_logic_vector(7 downto 0);
        -- External authorisation (with ExtAuth_g; request fields on Auth_Hdr)
        Ext_Req        : out   std_logic;
        Ext_RspValid   : in    std_logic;
        Ext_RspAccept  : in    std_logic;
        -- Memory access
        MemCmd_Valid   : out   std_logic;
        MemCmd_Ready   : in    std_logic;
        MemCmd_Write   : out   std_logic;
        MemCmd_Addr    : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        MemCmd_Size    : out   std_logic_vector(23 downto 0);
        MemCmd_Single  : out   std_logic;
        MemWr_Data     : out   std_logic_vector(7 downto 0);
        MemWr_Valid    : out   std_logic;
        MemWr_Ready    : in    std_logic;
        MemRd_Data     : in    std_logic_vector(7 downto 0);
        MemRd_Valid    : in    std_logic;
        MemRd_Ready    : out   std_logic;
        Mem_Busy       : in    std_logic;
        Mem_Err        : in    std_logic;
        Mem_ErrClr     : out   std_logic;
        -- Reply encoder
        Rep_Valid      : out   std_logic;
        Rep_Ready      : in    std_logic;
        Rep_Hdr        : out   CmdHeader_t;
        Rep_Status     : out   std_logic_vector(7 downto 0);
        Rep_Read       : out   std_logic;
        Rep_LenField   : out   std_logic_vector(23 downto 0);
        Rep_DataCount  : out   std_logic_vector(23 downto 0);
        RepData_Valid  : out   std_logic;
        RepData_Ready  : in    std_logic;
        RepData_Byte   : out   std_logic_vector(7 downto 0);
        RepEnd_Valid   : out   std_logic;
        RepEnd_Ready   : in    std_logic;
        RepEnd_Eep     : out   std_logic;
        -- Indication of every command with an intact header (one-cycle event)
        Ind_Valid      : out   std_logic;
        Ind_Hdr        : out   CmdHeader_t;
        Ind_Status     : out   std_logic_vector(7 downto 0);
        Ind_Replied    : out   std_logic;
        -- ECC of the write buffer
        Ecc_BufSec     : out   std_logic;
        Ecc_BufDed     : out   std_logic;
        BufInj_BitFlip : in    std_logic_vector(eccCodewordWidth(8) - 1 downto 0) := (others => '0');
        BufInj_Valid   : in    std_logic                                          := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_target_ctrl is

    type Fsm_t is (
        Idle_s, Auth_s, Ext_s, Drain_s, WrData_s, RdWait_s, RdExec_s, RdEnd_s, RmwData_s, RmwExt_s, RmwRead_s,
        RmwWrite_s, Reply_s, RepData_s, RepEnd_s, Done_s
    );

    type Bytes8_t is array (0 to 7) of std_logic_vector(7 downto 0);
    type Bytes4_t is array (0 to 3) of std_logic_vector(7 downto 0);

    type TwoProcess_r is record
        Fsm        : Fsm_t;
        H          : CmdHeader_t;
        Kind       : CmdKind_t;
        HdrStatus  : std_logic_vector(7 downto 0);
        ExtReject  : std_logic;
        NoReply    : std_logic;
        Status     : std_logic_vector(7 downto 0);
        AuthStart  : std_logic;
        -- End of the packet
        EndSeen    : std_logic;
        EndEep     : std_logic;
        EndImm     : std_logic;
        EndEarly   : std_logic;
        EndExcess  : std_logic;
        EndCrcOk   : std_logic;
        -- Write buffer and chunks
        Received   : unsigned(23 downto 0);
        Committed  : unsigned(23 downto 0);
        Pump       : unsigned(23 downto 0);
        CommitEn   : std_logic;
        Drain      : std_logic;
        BufErr     : std_logic;
        -- Memory command
        CmdPend    : std_logic;
        CmdWrite   : std_logic;
        CmdAddr    : unsigned(39 downto 0);
        CmdSize    : unsigned(23 downto 0);
        CmdSingle  : std_logic;
        ErrClr     : std_logic;
        -- Read and read-modify-write
        Fwd        : unsigned(23 downto 0);
        RmwBuf     : Bytes8_t;
        RmwIdx     : natural range 0 to 8;
        RdBuf      : Bytes4_t;
        NewBuf     : Bytes4_t;
        Idx        : natural range 0 to 4;
        RmwN       : natural range 0 to 4;
        -- Reply
        RepRead    : std_logic;
        RepLen     : unsigned(23 downto 0);
        RepCount   : natural range 0 to 4;
        -- Events
        IndValid   : std_logic;
        IndReplied : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Write buffer
    signal FifoIn_Valid  : std_logic;
    signal FifoIn_Ready  : std_logic;
    signal FifoOut_Data  : std_logic_vector(7 downto 0);
    signal FifoOut_Valid : std_logic;
    signal FifoOut_Ready : std_logic;
    signal FifoOut_Sec   : std_logic;
    signal FifoOut_Ded   : std_logic;
    signal FifoEmpty     : std_logic;

    -- Status of a write after the end of the packet (architecture D9): end of the packet, then Data CRC. A write
    -- with a header error or rejected by the external authorisation ends in Drain_s instead.
    function writeEndStatus (rr : TwoProcess_r) return std_logic_vector is
    begin
        if rr.EndEep = '1' then
            return StatusEep_c;
        elsif rr.EndEarly = '1' then
            return StatusEarlyEop_c;
        elsif rr.EndExcess = '1' then
            return StatusTooMuch_c;
        elsif rr.EndCrcOk = '0' then
            return StatusDataCrc_c;
        else
            return StatusOk_c;
        end if;
    end function;

begin

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Avail_v  : unsigned(23 downto 0);
        variable Len_v    : unsigned(23 downto 0);
        variable Size_v   : unsigned(23 downto 0);
        variable Push_v   : boolean;
        variable PumpOk_v : boolean;
        variable Ack_v    : boolean;
    begin
        v           := r;
        v.AuthStart := '0';
        v.ErrClr    := '0';
        v.IndValid  := '0';

        Len_v := unsigned(r.H.Len);

        -- Default handshakes
        Hdr_Ready     <= '0';
        Data_Ready    <= '0';
        End_Ready     <= '0';
        FifoIn_Valid  <= '0';
        MemRd_Ready   <= '0';
        RepData_Valid <= '0';
        RepData_Byte  <= MemRd_Data;
        RepEnd_Valid  <= '0';
        RepEnd_Eep    <= '0';
        Rep_Valid     <= '0';
        Ext_Req       <= '0';
        Push_v        := false;

        -- Memory command handshake; the data of a write command follows its command
        if r.CmdPend = '1' and MemCmd_Ready = '1' then
            v.CmdPend := '0';
            if r.CmdWrite = '1' and r.Fsm = WrData_s then
                v.Pump := v.Pump + r.CmdSize;
            end if;
        end if;

        -- Write data from the buffer to the memory (Pump bytes committed), or discarded (Drain)
        PumpOk_v := r.Pump /= 0 and FifoOut_Valid = '1' and MemWr_Ready = '1' and r.Fsm = WrData_s;
        if PumpOk_v then
            v.Pump := r.Pump - 1;
        end if;
        -- A double error in a word written to memory gives status 1; a discarded word belongs to a command with an
        -- error status already
        if FifoOut_Valid = '1' and FifoOut_Ded = '1' and PumpOk_v then
            v.BufErr := '1';
        end if;

        case r.Fsm is

            when Idle_s =>
                if Hdr_Valid = '1' then
                    v.H         := Hdr;
                    v.Kind      := cmdKind(cmdCode(Hdr.Instr));
                    v.AuthStart := '1';
                    v.ExtReject := '0';
                    v.NoReply   := not Hdr.Instr(InstrReply_c);
                    v.EndSeen   := '0';
                    v.Received  := (others => '0');
                    v.Committed := (others => '0');
                    v.Pump      := (others => '0');
                    v.CommitEn  := '0';
                    v.Drain     := '0';
                    v.BufErr    := '0';
                    v.Fwd       := (others => '0');
                    v.RmwIdx    := 0;
                    v.Idx       := 0;
                    v.ErrClr    := '1';
                    v.Fsm       := Auth_s;
                end if;

            when Auth_s =>
                if Auth_Done = '1' then
                    v.HdrStatus := Auth_Status;
                    if Auth_Discard = '1' then
                        -- ECSS 5.3.3.4.6: reserved packet type, discarded without reply
                        v.NoReply   := '1';
                        v.HdrStatus := StatusUnused_c;
                        Hdr_Ready   <= '1';
                        v.Fsm       := Drain_s;
                    elsif Auth_Status /= StatusOk_c then
                        Hdr_Ready <= '1';
                        v.Fsm     := Drain_s;
                    elsif ExtAuth_g and r.Kind /= CmdRmw then
                        v.Fsm := Ext_s;
                    else
                        Hdr_Ready <= '1';

                        case r.Kind is

                            when CmdWrite =>
                                -- Non-verified writes are committed while they arrive (ECSS 5.3.3.6.9)
                                v.CommitEn := not r.H.Instr(InstrVerify_c);
                                v.Fsm      := WrData_s;

                            when CmdRead =>
                                v.Fsm := RdWait_s;

                            when others =>
                                v.Fsm := RmwData_s;

                        end case;

                    end if;
                end if;

            when Ext_s =>
                -- ECSS 5.3.3.5.1, 5.4.3.5.1: authorisation by the user application
                Ext_Req <= '1';
                if Ext_RspValid = '1' then
                    Hdr_Ready <= '1';
                    if Ext_RspAccept = '0' then
                        v.ExtReject := '1';
                        v.Fsm       := Drain_s;
                    elsif r.Kind = CmdWrite then
                        v.CommitEn := not r.H.Instr(InstrVerify_c);
                        v.Fsm      := WrData_s;
                    else
                        v.Fsm := RdWait_s;
                    end if;
                end if;

            when Drain_s =>
                -- Rejected command: the rest of the packet is discarded
                Data_Ready <= '1';
                End_Ready  <= '1';
                if End_Valid = '1' then
                    v.EndEep    := End_Eep;
                    v.EndImm    := End_Immediate;
                    v.EndEarly  := End_Early;
                    v.EndExcess := End_Excess;
                    v.EndCrcOk  := End_CrcOk;
                    v.Fsm       := Done_s;
                    if End_Eep = '1' and End_Immediate = '1' then
                        -- ECSS 5.3.3.4.3: EEP immediately after the header, no reply
                        v.NoReply := '1';
                        v.Status  := StatusEep_c;
                    elsif r.HdrStatus /= StatusOk_c then
                        v.Status := r.HdrStatus;
                        if r.NoReply = '0' then
                            v.Fsm := Reply_s;
                        end if;
                    else
                        -- External authorisation rejected (a write or a read; a read-modify-write is authorised
                        -- after its data is checked, in RmwExt_s). An early EOP occurs only in a write.
                        v.Status := StatusNotAuth_c;
                        if End_Eep = '1' then
                            v.Status := StatusEep_c;
                        elsif End_Early = '1' then
                            v.Status := StatusEarlyEop_c;
                        elsif End_Excess = '1' then
                            v.Status := StatusTooMuch_c;
                        elsif r.Kind = CmdWrite and End_CrcOk = '0' then
                            v.Status := StatusDataCrc_c;
                        end if;
                        if r.NoReply = '0' then
                            v.Fsm := Reply_s;
                        end if;
                    end if;
                    v.RepRead  := '0';
                    v.RepLen   := (others => '0');
                    v.RepCount := 0;
                    if r.Kind = CmdRead or r.Kind = CmdRmw then
                        v.RepRead := '1';
                    end if;
                end if;

            when WrData_s =>
                -- Data into the buffer
                if r.EndSeen = '0' then
                    Data_Ready   <= FifoIn_Ready;
                    FifoIn_Valid <= Data_Valid;
                    if Data_Valid = '1' and FifoIn_Ready = '1' then
                        Push_v     := true;
                        v.Received := r.Received + 1;
                    end if;
                    End_Ready <= '1';
                    if End_Valid = '1' then
                        v.EndSeen   := '1';
                        v.EndEep    := End_Eep;
                        v.EndImm    := End_Immediate;
                        v.EndEarly  := End_Early;
                        v.EndExcess := End_Excess;
                        v.EndCrcOk  := End_CrcOk;
                        if End_Eep = '1' and End_Immediate = '1' then
                            v.NoReply  := '1';
                            v.CommitEn := '0';
                        elsif End_Eep = '1' or End_Early = '1' then
                            -- ECSS 5.3.3.6.6, 5.3.3.6.8, 5.3.3.6.11, 5.3.3.6.13: the incomplete chunk is not written
                            v.CommitEn := '0';
                        elsif r.H.Instr(InstrVerify_c) = '1' then
                            -- ECSS 5.3.3.6.4: verified data is written when the Data CRC and the length are correct
                            if End_Excess = '0' and End_CrcOk = '1' then
                                v.CommitEn := '1';
                            end if;
                        end if;
                    end if;
                end if;

                -- Chunks complete in the buffer (all remaining bytes once the Data Length is received)
                Avail_v := r.Received - r.Committed;
                if r.CmdPend = '0' and r.CommitEn = '1' and Avail_v /= 0 and
                   (Avail_v >= ChunkBytes_g or r.Received = Len_v) then
                    if Avail_v >= ChunkBytes_g then
                        Size_v := to_unsigned(ChunkBytes_g, 24);
                    else
                        Size_v := Avail_v;
                    end if;
                    v.CmdPend   := '1';
                    v.CmdWrite  := '1';
                    v.CmdSingle := not r.H.Instr(InstrInc_c);
                    if r.H.Instr(InstrInc_c) = '1' then
                        v.CmdAddr := unsigned(r.H.Addr) + resize(r.Committed, 40);
                    else
                        v.CmdAddr := unsigned(r.H.Addr);
                    end if;
                    v.CmdSize   := Size_v;
                    v.Committed := r.Committed + Size_v;
                end if;

                -- Bytes that are not committed are discarded once the committed bytes are written
                if r.EndSeen = '1' and r.CommitEn = '0' then
                    v.Drain := '1';
                end if;

                -- Completion: all committed bytes written, nothing left in the buffer, memory idle
                if r.EndSeen = '1' and r.CmdPend = '0' and r.Pump = 0 and FifoEmpty = '1' and Mem_Busy = '0' and
                   (r.CommitEn = '0' or r.Committed = Len_v) and v.CmdPend = '0' then
                    v.Status := writeEndStatus(r);
                    if r.EndEep = '1' and r.EndImm = '1' then
                        v.Status := StatusEep_c;
                    elsif v.Status = StatusOk_c and (Mem_Err = '1' or r.BufErr = '1') then
                        -- ECSS 5.3.3.10c: memory error
                        v.Status := StatusGeneral_c;
                    end if;
                    v.RepRead  := '0';
                    v.RepCount := 0;
                    if r.NoReply = '1' then
                        v.Fsm := Done_s;
                    else
                        v.Fsm := Reply_s;
                    end if;
                end if;

            when RdWait_s =>
                -- ECSS 5.4.3.4.8: the read is executed only when the packet ends right after the header
                Data_Ready <= '1';
                End_Ready  <= '1';
                if End_Valid = '1' then
                    v.EndEep    := End_Eep;
                    v.EndImm    := End_Immediate;
                    v.EndEarly  := '0';
                    v.EndExcess := End_Excess;
                    v.EndCrcOk  := '1';
                    v.RepRead   := '1';
                    v.RepCount  := 0;
                    v.RepLen    := (others => '0');
                    if End_Eep = '1' and End_Immediate = '1' then
                        v.NoReply := '1';
                        v.Status  := StatusEep_c;
                        v.Fsm     := Done_s;
                    elsif End_Eep = '1' then
                        v.Status := StatusEep_c;
                        v.Fsm    := Reply_s;
                    elsif End_Excess = '1' then
                        v.Status := StatusTooMuch_c;
                        v.Fsm    := Reply_s;
                    elsif Len_v = 0 then
                        -- ECSS 5.4.1.12 note: zero-length read, no memory access
                        v.Status := StatusOk_c;
                        v.Fsm    := Reply_s;
                    else
                        v.Status    := StatusOk_c;
                        v.CmdPend   := '1';
                        v.CmdWrite  := '0';
                        v.CmdSingle := not r.H.Instr(InstrInc_c);
                        v.CmdAddr   := unsigned(r.H.Addr);
                        v.CmdSize   := Len_v;
                        v.RepLen    := Len_v;
                        v.Fsm       := RdExec_s;
                    end if;
                end if;

            when RdExec_s =>
                -- Reply header with status 0, then the data as it is read (architecture D6)
                Rep_Valid <= '1';
                if Rep_Ready = '1' then
                    v.Fsm := RdEnd_s;
                end if;

            when RdEnd_s =>
                RepData_Valid <= MemRd_Valid when r.Fwd /= Len_v else '0';
                MemRd_Ready   <= RepData_Ready when r.Fwd /= Len_v else '0';
                if MemRd_Valid = '1' and RepData_Ready = '1' and r.Fwd /= Len_v then
                    v.Fwd := r.Fwd + 1;
                end if;
                if r.Fwd = Len_v and r.CmdPend = '0' and Mem_Busy = '0' then
                    -- ECSS 5.4.3.10c.1: a memory error ends the reply with an EEP
                    RepEnd_Valid <= '1';
                    RepEnd_Eep   <= Mem_Err;
                    if RepEnd_Ready = '1' then
                        if Mem_Err = '1' then
                            v.Status := StatusGeneral_c;
                        end if;
                        v.IndReplied := '1';
                        v.IndValid   := '1';
                        v.Fsm        := Idle_s;
                    end if;
                end if;

            when RmwData_s =>
                -- ECSS 5.5.3.4.8: data and mask are buffered and checked before the authorisation
                Data_Ready <= '1';
                if Data_Valid = '1' and r.RmwIdx < 8 then
                    v.RmwBuf(r.RmwIdx) := Data_Byte;
                    v.RmwIdx           := r.RmwIdx + 1;
                end if;
                End_Ready <= '1';
                if End_Valid = '1' then
                    v.EndEep    := End_Eep;
                    v.EndImm    := End_Immediate;
                    v.EndEarly  := End_Early;
                    v.EndExcess := End_Excess;
                    v.EndCrcOk  := End_CrcOk;
                    v.RepRead   := '1';
                    v.RepCount  := 0;
                    v.RepLen    := (others => '0');
                    v.RmwN      := to_integer(Len_v(3 downto 1));
                    if End_Eep = '1' and End_Immediate = '1' then
                        v.NoReply := '1';
                        v.Status  := StatusEep_c;
                        v.Fsm     := Done_s;
                    elsif End_Eep = '1' then
                        v.Status := StatusEep_c;
                        v.Fsm    := Reply_s;
                    elsif End_Early = '1' then
                        v.Status := StatusEarlyEop_c;
                        v.Fsm    := Reply_s;
                    elsif End_Excess = '1' then
                        v.Status := StatusTooMuch_c;
                        v.Fsm    := Reply_s;
                    elsif End_CrcOk = '0' then
                        v.Status := StatusDataCrc_c;
                        v.Fsm    := Reply_s;
                    elsif ExtAuth_g then
                        v.Fsm := RmwExt_s;
                    else
                        v.Fsm := RmwRead_s;
                    end if;
                end if;

            when RmwExt_s =>
                -- ECSS 5.5.3.5: authorisation by the user application after the data check
                Ext_Req <= '1';
                if Ext_RspValid = '1' then
                    if Ext_RspAccept = '1' then
                        v.Fsm := RmwRead_s;
                    else
                        v.Status := StatusNotAuth_c;
                        v.Fsm    := Reply_s;
                    end if;
                end if;

            when RmwRead_s =>
                if r.RmwN = 0 then
                    -- Zero bytes: no memory access
                    v.Status := StatusOk_c;
                    v.Fsm    := Reply_s;
                elsif r.Idx = 0 and r.CmdPend = '0' and r.EndSeen = '0' then
                    -- ECSS 5.5.3.6: read the bytes (EndSeen marks the command issued)
                    v.CmdPend   := '1';
                    v.CmdWrite  := '0';
                    v.CmdSingle := '0';
                    v.CmdAddr   := unsigned(r.H.Addr);
                    v.CmdSize   := to_unsigned(r.RmwN, 24);
                    v.EndSeen   := '1';
                else
                    MemRd_Ready <= '1';
                    if MemRd_Valid = '1' and r.Idx < r.RmwN then
                        v.RdBuf(r.Idx) := MemRd_Data;
                        v.Idx          := r.Idx + 1;
                    end if;
                    if r.Idx = r.RmwN and r.CmdPend = '0' and Mem_Busy = '0' then
                        v.RepLen := to_unsigned(r.RmwN, 24);
                        if Mem_Err = '1' then
                            -- ECSS 5.5.3.11: read error, nothing is written
                            v.Status   := StatusGeneral_c;
                            v.RepCount := 0;
                            v.Fsm      := Reply_s;
                        else

                            -- ECSS 5.5.3.7 note 3: (mask and data) or (not mask and read data)
                            for i in 0 to 3 loop
                                if i < r.RmwN then
                                    v.NewBuf(i) := (r.RmwBuf(r.RmwN + i) and r.RmwBuf(i)) or
                                                   (not r.RmwBuf(r.RmwN + i) and r.RdBuf(i));
                                end if;
                            end loop;

                            v.Idx       := 0;
                            v.CmdPend   := '1';
                            v.CmdWrite  := '1';
                            v.CmdSingle := '0';
                            v.CmdSize   := to_unsigned(r.RmwN, 24);
                            v.Fsm       := RmwWrite_s;
                        end if;
                    end if;
                end if;

            when RmwWrite_s =>
                if r.Idx < r.RmwN and MemWr_Ready = '1' then
                    v.Idx := r.Idx + 1;
                end if;
                if r.Idx = r.RmwN and r.CmdPend = '0' and Mem_Busy = '0' then
                    if Mem_Err = '1' then
                        v.Status := StatusGeneral_c;
                    else
                        v.Status := StatusOk_c;
                    end if;
                    v.RepCount := r.RmwN;
                    v.Fsm      := Reply_s;
                end if;

            when Reply_s =>
                Rep_Valid <= '1';
                if Rep_Ready = '1' then
                    v.Idx := 0;
                    if r.RepRead = '1' then
                        v.Fsm := RepData_s;
                    else
                        v.IndReplied := '1';
                        v.IndValid   := '1';
                        v.Fsm        := Idle_s;
                    end if;
                end if;

            when RepData_s =>
                -- Read data of a read-modify-write
                if r.Idx < r.RepCount then
                    RepData_Valid <= '1';
                    RepData_Byte  <= r.RdBuf(r.Idx);
                    if RepData_Ready = '1' then
                        v.Idx := r.Idx + 1;
                    end if;
                else
                    v.Fsm := RepEnd_s;
                end if;

            when RepEnd_s =>
                RepEnd_Valid <= '1';
                if RepEnd_Ready = '1' then
                    v.IndReplied := '1';
                    v.IndValid   := '1';
                    v.Fsm        := Idle_s;
                end if;

            when Done_s =>
                -- Command without reply
                v.IndReplied := '0';
                v.IndValid   := '1';
                v.Fsm        := Idle_s;

            -- Recovery state for an illegal state
            -- coverage off
            when others =>
                v.Fsm := Idle_s;
            -- coverage on

        end case;

        -- Write data of a read-modify-write from NewBuf, otherwise from the buffer
        if r.Fsm = RmwWrite_s then
            MemWr_Valid <= '1' when r.Idx < r.RmwN else '0';
            MemWr_Data  <= r.NewBuf(r.Idx mod 4);
        else
            MemWr_Valid <= FifoOut_Valid when r.Pump /= 0 and r.Fsm = WrData_s else '0';
            MemWr_Data  <= FifoOut_Data;
        end if;
        FifoOut_Ready <= '1' when PumpOk_v or (r.Drain = '1' and r.Pump = 0 and r.Fsm = WrData_s) else '0';

        r_next <= v;
    end process;

    -- Outputs
    Auth_Start    <= r.AuthStart;
    Auth_Hdr      <= r.H;
    MemCmd_Valid  <= r.CmdPend;
    MemCmd_Write  <= r.CmdWrite;
    MemCmd_Addr   <= std_logic_vector(r.CmdAddr(AxiAddrWidth_g - 1 downto 0));
    MemCmd_Size   <= std_logic_vector(r.CmdSize);
    MemCmd_Single <= r.CmdSingle;
    Mem_ErrClr    <= r.ErrClr;
    Rep_Hdr       <= r.H;
    Rep_Status    <= r.Status;
    Rep_Read      <= r.RepRead;
    Rep_LenField  <= std_logic_vector(r.RepLen);
    Rep_DataCount <= std_logic_vector(r.RepLen) when r.Fsm = RdExec_s else
                     std_logic_vector(to_unsigned(r.RepCount, 24));
    Ind_Valid     <= r.IndValid;
    Ind_Hdr       <= r.H;
    Ind_Status    <= r.Status;
    Ind_Replied   <= r.IndReplied;
    Ecc_BufSec    <= FifoOut_Sec and FifoOut_Valid and FifoOut_Ready;
    Ecc_BufDed    <= FifoOut_Ded and FifoOut_Valid and FifoOut_Ready;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm       <= Idle_s;
                r.AuthStart <= '0';
                r.CmdPend   <= '0';
                r.Pump      <= (others => '0');
                r.Drain     <= '0';
                r.ErrClr    <= '0';
                r.IndValid  <= '0';
            end if;
        end if;
    end process;

    -- Write buffer (verify buffer and chunks of non-verified writes)
    i_buf : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => 8,
            Depth_g => BufferBytes_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Data_Byte,
            In_Valid          => FifoIn_Valid,
            In_Ready          => FifoIn_Ready,
            Out_Data          => FifoOut_Data,
            Out_Valid         => FifoOut_Valid,
            Out_Ready         => FifoOut_Ready,
            Out_EccSec        => FifoOut_Sec,
            Out_EccDed        => FifoOut_Ded,
            Empty             => FifoEmpty,
            In_ErrInj_BitFlip => BufInj_BitFlip,
            In_ErrInj_Valid   => BufInj_Valid
        );

end architecture;
