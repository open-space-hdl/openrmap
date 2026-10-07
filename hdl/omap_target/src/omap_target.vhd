---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- RMAP Target (TG-1 to TG-5): receives commands on an N-Char stream, checks and authorises them,
-- executes write, read and read-modify-write commands on the Target memory through an AXI4 master
-- and sends the replies on an N-Char stream. One command is executed at a time.
--
-- Documentation: hdl/omap_target/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.omap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_target is
    generic (
        AxiAddrWidth_g : positive range 12 to 40 := 32;
        AxiDataWidth_g : positive                := 32;
        AxiMaxBeats_g  : positive range 1 to 256 := 16;
        BufferBytes_g  : positive                := 256;
        ChunkBytes_g   : positive                := 32;
        Windows_g      : natural range 0 to 8    := 4;
        ExtAuth_g      : boolean                 := false
    );
    port (
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        -- Commands (N-Char stream)
        S_Cmd_TData     : in    std_logic_vector(7 downto 0);
        S_Cmd_TLast     : in    std_logic;
        S_Cmd_TValid    : in    std_logic;
        S_Cmd_TReady    : out   std_logic;
        -- Replies (N-Char stream)
        M_Rep_TData     : out   std_logic_vector(7 downto 0);
        M_Rep_TLast     : out   std_logic;
        M_Rep_TValid    : out   std_logic;
        M_Rep_TReady    : in    std_logic;
        -- Configuration
        Cfg_La0         : in    std_logic_vector(7 downto 0);
        Cfg_La0En       : in    std_logic;
        Cfg_La1         : in    std_logic_vector(7 downto 0);
        Cfg_La1En       : in    std_logic;
        Cfg_DefLaEn     : in    std_logic;
        Cfg_Key         : in    std_logic_vector(7 downto 0);
        Cfg_KeyEn       : in    std_logic;
        Cfg_Win         : in    WinCfgArray_t(0 to Windows_g - 1);
        -- External authorisation (ExtAuth_g): request held until the response
        Auth_Valid      : out   std_logic;
        Auth_Tla        : out   std_logic_vector(7 downto 0);
        Auth_Instr      : out   std_logic_vector(7 downto 0);
        Auth_Key        : out   std_logic_vector(7 downto 0);
        Auth_Ila        : out   std_logic_vector(7 downto 0);
        Auth_Tid        : out   std_logic_vector(15 downto 0);
        Auth_Addr       : out   std_logic_vector(39 downto 0);
        Auth_Len        : out   std_logic_vector(23 downto 0);
        Auth_RspValid   : in    std_logic                    := '0';
        Auth_RspAccept  : in    std_logic                    := '0';
        -- Indication of every command with an intact header (one-cycle event)
        Ind_Valid       : out   std_logic;
        Ind_Tla         : out   std_logic_vector(7 downto 0);
        Ind_Instr       : out   std_logic_vector(7 downto 0);
        Ind_Ila         : out   std_logic_vector(7 downto 0);
        Ind_Tid         : out   std_logic_vector(15 downto 0);
        Ind_Addr        : out   std_logic_vector(39 downto 0);
        Ind_Len         : out   std_logic_vector(23 downto 0);
        Ind_Status      : out   std_logic_vector(7 downto 0);
        Ind_Replied     : out   std_logic;
        -- Discarded packets and replies sent (one-cycle events)
        Evt_HdrCrc      : out   std_logic;
        Evt_HdrShort    : out   std_logic;
        Evt_ReplyRx     : out   std_logic;
        Evt_RepSent     : out   std_logic;
        -- ECC events (0 write buffer, 1 write data of the AXI master, 2 read data of the AXI master) and
        -- error injection into the next word written to a buffer (one bit or, with ErrInj_Double, two bits)
        Ecc_Sec         : out   std_logic_vector(2 downto 0);
        Ecc_Ded         : out   std_logic_vector(2 downto 0);
        ErrInj_Valid    : in    std_logic_vector(2 downto 0) := (others => '0');
        ErrInj_Double   : in    std_logic                    := '0';
        -- AXI4 master
        M_Axi_AwAddr    : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_AwLen     : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize    : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst   : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock    : out   std_logic;
        M_Axi_AwCache   : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt    : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid   : out   std_logic;
        M_Axi_AwReady   : in    std_logic;
        M_Axi_WData     : out   std_logic_vector(AxiDataWidth_g - 1 downto 0);
        M_Axi_WStrb     : out   std_logic_vector(AxiDataWidth_g / 8 - 1 downto 0);
        M_Axi_WLast     : out   std_logic;
        M_Axi_WValid    : out   std_logic;
        M_Axi_WReady    : in    std_logic;
        M_Axi_BResp     : in    std_logic_vector(1 downto 0);
        M_Axi_BValid    : in    std_logic;
        M_Axi_BReady    : out   std_logic;
        M_Axi_ArAddr    : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_ArLen     : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize    : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst   : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock    : out   std_logic;
        M_Axi_ArCache   : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt    : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid   : out   std_logic;
        M_Axi_ArReady   : in    std_logic;
        M_Axi_RData     : in    std_logic_vector(AxiDataWidth_g - 1 downto 0);
        M_Axi_RResp     : in    std_logic_vector(1 downto 0);
        M_Axi_RLast     : in    std_logic;
        M_Axi_RValid    : in    std_logic;
        M_Axi_RReady    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_target is

    -- Injection patterns: bit 3, or bits 3 and 5, of the codeword
    function injPattern (
        width  : positive;
        double : std_logic) return std_logic_vector is
        variable Pat_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        Pat_v(3) := '1';
        if double = '1' then
            Pat_v(5) := '1';
        end if;
        return Pat_v;
    end function;

    -- Decoder to controller
    signal HdrValid  : std_logic;
    signal HdrReady  : std_logic;
    signal HdrDec    : CmdHeader_t;
    signal DataValid : std_logic;
    signal DataReady : std_logic;
    signal DataByte  : std_logic_vector(7 downto 0);
    signal EndValid  : std_logic;
    signal EndReady  : std_logic;
    signal EndEep    : std_logic;
    signal EndImm    : std_logic;
    signal EndEarly  : std_logic;
    signal EndExcess : std_logic;
    signal EndCrcOk  : std_logic;

    -- Authorisation
    signal AuthStart   : std_logic;
    signal AuthHdr     : CmdHeader_t;
    signal AuthDone    : std_logic;
    signal AuthDiscard : std_logic;
    signal AuthStatus  : std_logic_vector(7 downto 0);

    -- Memory access
    signal MemCmdValid  : std_logic;
    signal MemCmdReady  : std_logic;
    signal MemCmdWrite  : std_logic;
    signal MemCmdAddr   : std_logic_vector(AxiAddrWidth_g - 1 downto 0);
    signal MemCmdSize   : std_logic_vector(23 downto 0);
    signal MemCmdSingle : std_logic;
    signal MemWrData    : std_logic_vector(7 downto 0);
    signal MemWrValid   : std_logic;
    signal MemWrReady   : std_logic;
    signal MemRdData    : std_logic_vector(7 downto 0);
    signal MemRdValid   : std_logic;
    signal MemRdReady   : std_logic;
    signal MemBusy      : std_logic;
    signal MemErr       : std_logic;
    signal MemErrClr    : std_logic;

    -- Reply encoder
    signal RepValid     : std_logic;
    signal RepReady     : std_logic;
    signal RepHdr       : CmdHeader_t;
    signal RepStatus    : std_logic_vector(7 downto 0);
    signal RepRead      : std_logic;
    signal RepLenField  : std_logic_vector(23 downto 0);
    signal RepDataCount : std_logic_vector(23 downto 0);
    signal RepDataValid : std_logic;
    signal RepDataReady : std_logic;
    signal RepDataByte  : std_logic_vector(7 downto 0);
    signal RepEndValid  : std_logic;
    signal RepEndReady  : std_logic;
    signal RepEndEep    : std_logic;

    signal IndHdr : CmdHeader_t;

begin

    -- TG-1
    i_rx : entity work.omap_target_rx
        port map (
            Clk           => Clk,
            Rst           => Rst,
            In_Data       => S_Cmd_TData,
            In_Last       => S_Cmd_TLast,
            In_Valid      => S_Cmd_TValid,
            In_Ready      => S_Cmd_TReady,
            Hdr_Valid     => HdrValid,
            Hdr_Ready     => HdrReady,
            Hdr           => HdrDec,
            Data_Valid    => DataValid,
            Data_Ready    => DataReady,
            Data_Byte     => DataByte,
            End_Valid     => EndValid,
            End_Ready     => EndReady,
            End_Eep       => EndEep,
            End_Immediate => EndImm,
            End_Early     => EndEarly,
            End_Excess    => EndExcess,
            End_CrcOk     => EndCrcOk,
            Evt_HdrCrc    => Evt_HdrCrc,
            Evt_HdrShort  => Evt_HdrShort,
            Evt_ReplyRx   => Evt_ReplyRx
        );

    -- TG-2
    i_auth : entity work.omap_target_auth
        generic map (
            AxiAddrWidth_g => AxiAddrWidth_g,
            AxiDataWidth_g => AxiDataWidth_g,
            BufferBytes_g  => BufferBytes_g,
            Windows_g      => Windows_g
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            Cfg_La0     => Cfg_La0,
            Cfg_La0En   => Cfg_La0En,
            Cfg_La1     => Cfg_La1,
            Cfg_La1En   => Cfg_La1En,
            Cfg_DefLaEn => Cfg_DefLaEn,
            Cfg_Key     => Cfg_Key,
            Cfg_KeyEn   => Cfg_KeyEn,
            Cfg_Win     => Cfg_Win,
            Start       => AuthStart,
            Hdr         => AuthHdr,
            Done        => AuthDone,
            Discard     => AuthDiscard,
            Status      => AuthStatus
        );

    -- TG-3
    i_ctrl : entity work.omap_target_ctrl
        generic map (
            AxiAddrWidth_g => AxiAddrWidth_g,
            AxiDataWidth_g => AxiDataWidth_g,
            BufferBytes_g  => BufferBytes_g,
            ChunkBytes_g   => ChunkBytes_g,
            ExtAuth_g      => ExtAuth_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Hdr_Valid      => HdrValid,
            Hdr_Ready      => HdrReady,
            Hdr            => HdrDec,
            Data_Valid     => DataValid,
            Data_Ready     => DataReady,
            Data_Byte      => DataByte,
            End_Valid      => EndValid,
            End_Ready      => EndReady,
            End_Eep        => EndEep,
            End_Immediate  => EndImm,
            End_Early      => EndEarly,
            End_Excess     => EndExcess,
            End_CrcOk      => EndCrcOk,
            Auth_Start     => AuthStart,
            Auth_Hdr       => AuthHdr,
            Auth_Done      => AuthDone,
            Auth_Discard   => AuthDiscard,
            Auth_Status    => AuthStatus,
            Ext_Req        => Auth_Valid,
            Ext_RspValid   => Auth_RspValid,
            Ext_RspAccept  => Auth_RspAccept,
            MemCmd_Valid   => MemCmdValid,
            MemCmd_Ready   => MemCmdReady,
            MemCmd_Write   => MemCmdWrite,
            MemCmd_Addr    => MemCmdAddr,
            MemCmd_Size    => MemCmdSize,
            MemCmd_Single  => MemCmdSingle,
            MemWr_Data     => MemWrData,
            MemWr_Valid    => MemWrValid,
            MemWr_Ready    => MemWrReady,
            MemRd_Data     => MemRdData,
            MemRd_Valid    => MemRdValid,
            MemRd_Ready    => MemRdReady,
            Mem_Busy       => MemBusy,
            Mem_Err        => MemErr,
            Mem_ErrClr     => MemErrClr,
            Rep_Valid      => RepValid,
            Rep_Ready      => RepReady,
            Rep_Hdr        => RepHdr,
            Rep_Status     => RepStatus,
            Rep_Read       => RepRead,
            Rep_LenField   => RepLenField,
            Rep_DataCount  => RepDataCount,
            RepData_Valid  => RepDataValid,
            RepData_Ready  => RepDataReady,
            RepData_Byte   => RepDataByte,
            RepEnd_Valid   => RepEndValid,
            RepEnd_Ready   => RepEndReady,
            RepEnd_Eep     => RepEndEep,
            Ind_Valid      => Ind_Valid,
            Ind_Hdr        => IndHdr,
            Ind_Status     => Ind_Status,
            Ind_Replied    => Ind_Replied,
            Ecc_BufSec     => Ecc_Sec(0),
            Ecc_BufDed     => Ecc_Ded(0),
            BufInj_BitFlip => injPattern(eccCodewordWidth(8), ErrInj_Double),
            BufInj_Valid   => ErrInj_Valid(0)
        );

    -- TG-4
    i_mem : entity work.omap_target_mem
        generic map (
            AxiAddrWidth_g => AxiAddrWidth_g,
            AxiDataWidth_g => AxiDataWidth_g,
            AxiMaxBeats_g  => AxiMaxBeats_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            Cmd_Valid     => MemCmdValid,
            Cmd_Ready     => MemCmdReady,
            Cmd_Write     => MemCmdWrite,
            Cmd_Addr      => MemCmdAddr,
            Cmd_Size      => MemCmdSize,
            Cmd_Single    => MemCmdSingle,
            Wr_Data       => MemWrData,
            Wr_Valid      => MemWrValid,
            Wr_Ready      => MemWrReady,
            Rd_Data       => MemRdData,
            Rd_Valid      => MemRdValid,
            Rd_Ready      => MemRdReady,
            Busy          => MemBusy,
            Err           => MemErr,
            ErrClr        => MemErrClr,
            Ecc_WrSec     => Ecc_Sec(1),
            Ecc_WrDed     => Ecc_Ded(1),
            Ecc_RdSec     => Ecc_Sec(2),
            Ecc_RdDed     => Ecc_Ded(2),
            WrInj_BitFlip => injPattern(eccCodewordWidth(AxiDataWidth_g), ErrInj_Double),
            WrInj_Valid   => ErrInj_Valid(1),
            RdInj_BitFlip => injPattern(eccCodewordWidth(AxiDataWidth_g + 1), ErrInj_Double),
            RdInj_Valid   => ErrInj_Valid(2),
            M_Axi_AwAddr  => M_Axi_AwAddr,
            M_Axi_AwLen   => M_Axi_AwLen,
            M_Axi_AwSize  => M_Axi_AwSize,
            M_Axi_AwBurst => M_Axi_AwBurst,
            M_Axi_AwLock  => M_Axi_AwLock,
            M_Axi_AwCache => M_Axi_AwCache,
            M_Axi_AwProt  => M_Axi_AwProt,
            M_Axi_AwValid => M_Axi_AwValid,
            M_Axi_AwReady => M_Axi_AwReady,
            M_Axi_WData   => M_Axi_WData,
            M_Axi_WStrb   => M_Axi_WStrb,
            M_Axi_WLast   => M_Axi_WLast,
            M_Axi_WValid  => M_Axi_WValid,
            M_Axi_WReady  => M_Axi_WReady,
            M_Axi_BResp   => M_Axi_BResp,
            M_Axi_BValid  => M_Axi_BValid,
            M_Axi_BReady  => M_Axi_BReady,
            M_Axi_ArAddr  => M_Axi_ArAddr,
            M_Axi_ArLen   => M_Axi_ArLen,
            M_Axi_ArSize  => M_Axi_ArSize,
            M_Axi_ArBurst => M_Axi_ArBurst,
            M_Axi_ArLock  => M_Axi_ArLock,
            M_Axi_ArCache => M_Axi_ArCache,
            M_Axi_ArProt  => M_Axi_ArProt,
            M_Axi_ArValid => M_Axi_ArValid,
            M_Axi_ArReady => M_Axi_ArReady,
            M_Axi_RData   => M_Axi_RData,
            M_Axi_RResp   => M_Axi_RResp,
            M_Axi_RLast   => M_Axi_RLast,
            M_Axi_RValid  => M_Axi_RValid,
            M_Axi_RReady  => M_Axi_RReady
        );

    -- TG-5
    i_tx : entity work.omap_target_tx
        port map (
            Clk           => Clk,
            Rst           => Rst,
            Rep_Valid     => RepValid,
            Rep_Ready     => RepReady,
            Rep_Hdr       => RepHdr,
            Rep_Status    => RepStatus,
            Rep_Read      => RepRead,
            Rep_LenField  => RepLenField,
            Rep_DataCount => RepDataCount,
            Data_Valid    => RepDataValid,
            Data_Ready    => RepDataReady,
            Data_Byte     => RepDataByte,
            End_Valid     => RepEndValid,
            End_Ready     => RepEndReady,
            End_Eep       => RepEndEep,
            Out_Data      => M_Rep_TData,
            Out_Last      => M_Rep_TLast,
            Out_Valid     => M_Rep_TValid,
            Out_Ready     => M_Rep_TReady,
            Evt_Sent      => Evt_RepSent
        );

    -- Header fields of the external authorisation request and of the indication
    Auth_Tla   <= AuthHdr.Tla;
    Auth_Instr <= AuthHdr.Instr;
    Auth_Key   <= AuthHdr.Key;
    Auth_Ila   <= AuthHdr.Ila;
    Auth_Tid   <= AuthHdr.Tid;
    Auth_Addr  <= AuthHdr.Addr;
    Auth_Len   <= AuthHdr.Len;
    Ind_Tla    <= IndHdr.Tla;
    Ind_Instr  <= IndHdr.Instr;
    Ind_Ila    <= IndHdr.Ila;
    Ind_Tid    <= IndHdr.Tid;
    Ind_Addr   <= IndHdr.Addr;
    Ind_Len    <= IndHdr.Len;

end architecture;
