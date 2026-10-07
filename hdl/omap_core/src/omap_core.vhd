---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- OpenRMAP core: RMAP Target and RMAP Initiator (ECSS-E-ST-50-52C) with packet routing to and from
-- a SpaceWire port, a user port for packets of other protocols and the register file.
--
-- Documentation: hdl/omap_core/docs/specification.md, docs/user_guide.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.omap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_core is
    generic (
        -- Functions
        Target_g          : boolean                          := true;
        Initiator_g       : boolean                          := true;
        Passthrough_g     : boolean                          := true;
        -- Target
        AxiAddrWidth_g    : positive range 12 to 40          := 32;
        AxiDataWidth_g    : positive                         := 32;
        AxiMaxBeats_g     : positive range 1 to 256          := 16;
        BufferBytes_g     : positive range 1 to 65535        := 256;
        ChunkBytes_g      : positive range 1 to 65535        := 32;
        Windows_g         : natural range 0 to WinMax_c      := 4;
        ExtAuth_g         : boolean                          := false;
        -- Initiator
        TgtAddrBytes_g    : natural range 0 to 16            := 8;
        Transactions_g    : natural range 0 to 64            := 8;
        -- Reset values of the register file
        La0_g             : std_logic_vector(7 downto 0)     := x"FE";
        La1_g             : std_logic_vector(7 downto 0)     := x"FE";
        DefLaEn_g         : std_logic                        := '1';
        Key_g             : std_logic_vector(7 downto 0)     := x"00";
        TickCycles_g      : natural range 0 to 65535         := 99;
        Timeout_g         : natural range 0 to 65535         := 0;
        WinInit_g         : WinCfgArray_t(0 to WinMax_c - 1) := WinInitOpen_c
    );
    port (
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- Packets from and to the SpaceWire port (N-Char streams)
        S_Pkt_TData        : in    std_logic_vector(7 downto 0);
        S_Pkt_TLast        : in    std_logic;
        S_Pkt_TValid       : in    std_logic;
        S_Pkt_TReady       : out   std_logic;
        M_Pkt_TData        : out   std_logic_vector(7 downto 0);
        M_Pkt_TLast        : out   std_logic;
        M_Pkt_TValid       : out   std_logic;
        M_Pkt_TReady       : in    std_logic;
        -- User port: packets of other protocols (Passthrough_g)
        M_User_TData       : out   std_logic_vector(7 downto 0);
        M_User_TLast       : out   std_logic;
        M_User_TValid      : out   std_logic;
        M_User_TReady      : in    std_logic                                                     := '1';
        S_User_TData       : in    std_logic_vector(7 downto 0)                                  := (others => '0');
        S_User_TLast       : in    std_logic                                                     := '0';
        S_User_TValid      : in    std_logic                                                     := '0';
        S_User_TReady      : out   std_logic;
        -- Register file
        S_AxiLite_ArAddr   : in    std_logic_vector(9 downto 0);
        S_AxiLite_ArValid  : in    std_logic;
        S_AxiLite_ArReady  : out   std_logic;
        S_AxiLite_AwAddr   : in    std_logic_vector(9 downto 0);
        S_AxiLite_AwValid  : in    std_logic;
        S_AxiLite_AwReady  : out   std_logic;
        S_AxiLite_WData    : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb    : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid   : in    std_logic;
        S_AxiLite_WReady   : out   std_logic;
        S_AxiLite_BResp    : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid   : out   std_logic;
        S_AxiLite_BReady   : in    std_logic;
        S_AxiLite_RData    : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp    : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid   : out   std_logic;
        S_AxiLite_RReady   : in    std_logic;
        Irq                : out   std_logic;
        -- Target memory (AXI4 master, Target_g)
        M_Axi_AwAddr       : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_AwLen        : out   std_logic_vector(7 downto 0);
        M_Axi_AwSize       : out   std_logic_vector(2 downto 0);
        M_Axi_AwBurst      : out   std_logic_vector(1 downto 0);
        M_Axi_AwLock       : out   std_logic;
        M_Axi_AwCache      : out   std_logic_vector(3 downto 0);
        M_Axi_AwProt       : out   std_logic_vector(2 downto 0);
        M_Axi_AwValid      : out   std_logic;
        M_Axi_AwReady      : in    std_logic                                                     := '0';
        M_Axi_WData        : out   std_logic_vector(AxiDataWidth_g - 1 downto 0);
        M_Axi_WStrb        : out   std_logic_vector(AxiDataWidth_g / 8 - 1 downto 0);
        M_Axi_WLast        : out   std_logic;
        M_Axi_WValid       : out   std_logic;
        M_Axi_WReady       : in    std_logic                                                     := '0';
        M_Axi_BResp        : in    std_logic_vector(1 downto 0)                                  := "00";
        M_Axi_BValid       : in    std_logic                                                     := '0';
        M_Axi_BReady       : out   std_logic;
        M_Axi_ArAddr       : out   std_logic_vector(AxiAddrWidth_g - 1 downto 0);
        M_Axi_ArLen        : out   std_logic_vector(7 downto 0);
        M_Axi_ArSize       : out   std_logic_vector(2 downto 0);
        M_Axi_ArBurst      : out   std_logic_vector(1 downto 0);
        M_Axi_ArLock       : out   std_logic;
        M_Axi_ArCache      : out   std_logic_vector(3 downto 0);
        M_Axi_ArProt       : out   std_logic_vector(2 downto 0);
        M_Axi_ArValid      : out   std_logic;
        M_Axi_ArReady      : in    std_logic                                                     := '0';
        M_Axi_RData        : in    std_logic_vector(AxiDataWidth_g - 1 downto 0)                 := (others => '0');
        M_Axi_RResp        : in    std_logic_vector(1 downto 0)                                  := "00";
        M_Axi_RLast        : in    std_logic                                                     := '0';
        M_Axi_RValid       : in    std_logic                                                     := '0';
        M_Axi_RReady       : out   std_logic;
        -- External authorisation of the Target (ExtAuth_g): request held until the response
        Auth_Valid         : out   std_logic;
        Auth_Tla           : out   std_logic_vector(7 downto 0);
        Auth_Instr         : out   std_logic_vector(7 downto 0);
        Auth_Key           : out   std_logic_vector(7 downto 0);
        Auth_Ila           : out   std_logic_vector(7 downto 0);
        Auth_Tid           : out   std_logic_vector(15 downto 0);
        Auth_Addr          : out   std_logic_vector(39 downto 0);
        Auth_Len           : out   std_logic_vector(23 downto 0);
        Auth_RspValid      : in    std_logic                                                     := '0';
        Auth_RspAccept     : in    std_logic                                                     := '0';
        -- Indication of every command of the Target with an intact header (one-cycle event)
        Ind_Valid          : out   std_logic;
        Ind_Tla            : out   std_logic_vector(7 downto 0);
        Ind_Instr          : out   std_logic_vector(7 downto 0);
        Ind_Ila            : out   std_logic_vector(7 downto 0);
        Ind_Tid            : out   std_logic_vector(15 downto 0);
        Ind_Addr           : out   std_logic_vector(39 downto 0);
        Ind_Len            : out   std_logic_vector(23 downto 0);
        Ind_Status         : out   std_logic_vector(7 downto 0);
        Ind_Replied        : out   std_logic;
        -- Initiator requests (Initiator_g)
        S_Req_Valid        : in    std_logic                                                     := '0';
        S_Req_Ready        : out   std_logic;
        S_Req_Code         : in    std_logic_vector(3 downto 0)                                  := "0000";
        S_Req_TgtAddr      : in    std_logic_vector(maximum(TgtAddrBytes_g, 1) * 8 - 1 downto 0) := (others => '0');
        S_Req_TgtAddrLen   : in    std_logic_vector(4 downto 0)                                  := (others => '0');
        S_Req_Tla          : in    std_logic_vector(7 downto 0)                                  := x"FE";
        S_Req_Key          : in    std_logic_vector(7 downto 0)                                  := x"00";
        S_Req_ReplyAddr    : in    std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0)             := (others => '0');
        S_Req_ReplyAddrLen : in    std_logic_vector(3 downto 0)                                  := (others => '0');
        S_Req_Ila          : in    std_logic_vector(7 downto 0)                                  := x"FE";
        S_Req_Tid          : in    std_logic_vector(15 downto 0)                                 := (others => '0');
        S_Req_Addr         : in    std_logic_vector(39 downto 0)                                 := (others => '0');
        S_Req_Len          : in    std_logic_vector(23 downto 0)                                 := (others => '0');
        S_ReqData_TData    : in    std_logic_vector(7 downto 0)                                  := (others => '0');
        S_ReqData_TValid   : in    std_logic                                                     := '0';
        S_ReqData_TReady   : out   std_logic;
        -- Initiator confirmations and reply data
        M_Conf_Valid       : out   std_logic;
        M_Conf_Ready       : in    std_logic                                                     := '1';
        M_Conf_Tid         : out   std_logic_vector(15 downto 0);
        M_Conf_Instr       : out   std_logic_vector(7 downto 0);
        M_Conf_Status      : out   std_logic_vector(7 downto 0);
        M_Conf_Len         : out   std_logic_vector(23 downto 0);
        M_Conf_Error       : out   std_logic_vector(1 downto 0); -- 0 none, 1 data error, 2 timeout, 3 TID in use
        M_RepData_TData    : out   std_logic_vector(7 downto 0);
        M_RepData_TLast    : out   std_logic;
        M_RepData_TValid   : out   std_logic;
        M_RepData_TReady   : in    std_logic                                                     := '1'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_core is

    -- Generics shown by the register file
    function choose (
        cond : boolean;
        a    : natural;
        b    : natural) return natural is
    begin
        if cond then
            return a;
        else
            return b;
        end if;
    end function;

    -- Received packets to the Target and the Initiator, transmitted packets from them
    signal TgtCmdData  : std_logic_vector(7 downto 0);
    signal TgtCmdLast  : std_logic;
    signal TgtCmdValid : std_logic;
    signal TgtCmdReady : std_logic;
    signal TgtRepData  : std_logic_vector(7 downto 0);
    signal TgtRepLast  : std_logic;
    signal TgtRepValid : std_logic;
    signal TgtRepReady : std_logic;
    signal IniRepData  : std_logic_vector(7 downto 0);
    signal IniRepLast  : std_logic;
    signal IniRepValid : std_logic;
    signal IniRepReady : std_logic;
    signal IniCmdData  : std_logic_vector(7 downto 0);
    signal IniCmdLast  : std_logic;
    signal IniCmdValid : std_logic;
    signal IniCmdReady : std_logic;
    signal UsrTxValid  : std_logic;
    signal UsrRxReady  : std_logic;

    -- Configuration
    signal CfgLa0     : std_logic_vector(7 downto 0);
    signal CfgLa0En   : std_logic;
    signal CfgLa1     : std_logic_vector(7 downto 0);
    signal CfgLa1En   : std_logic;
    signal CfgDefLaEn : std_logic;
    signal CfgKey     : std_logic_vector(7 downto 0);
    signal CfgKeyEn   : std_logic;
    signal CfgWin     : WinCfgArray_t(0 to WinMax_c - 1);
    signal CfgTick    : std_logic_vector(15 downto 0);
    signal CfgTimeout : std_logic_vector(15 downto 0);

    -- Status and events
    signal IndValid      : std_logic;
    signal IndInstr      : std_logic_vector(7 downto 0);
    signal IndIla        : std_logic_vector(7 downto 0);
    signal IndTid        : std_logic_vector(15 downto 0);
    signal IndAddr       : std_logic_vector(39 downto 0);
    signal IndStatus     : std_logic_vector(7 downto 0);
    signal IndReplied    : std_logic;
    signal TgtHdrCrc     : std_logic;
    signal TgtHdrShort   : std_logic;
    signal TgtReplyRx    : std_logic;
    signal TgtRepSent    : std_logic;
    signal IniCmdSent    : std_logic;
    signal IniRepOk      : std_logic;
    signal IniHdrErr     : std_logic;
    signal IniDataErr    : std_logic;
    signal IniUnexpected : std_logic;
    signal IniTimeout    : std_logic;
    signal IniTidBusy    : std_logic;
    signal IniOpen       : std_logic_vector(7 downto 0);
    signal PktUser       : std_logic;
    signal PktDiscard    : std_logic;
    signal PktCmdRx      : std_logic;
    signal EccSec        : std_logic_vector(2 downto 0);
    signal EccDed        : std_logic_vector(2 downto 0);
    signal InjValid      : std_logic_vector(2 downto 0);
    signal InjDouble     : std_logic;

begin

    assert Target_g or Initiator_g
        report "omap_core: Target_g or Initiator_g must be true"
        severity failure;

    -- CO-1: packet demultiplexer
    i_demux : entity work.omap_core_demux
        generic map (
            Target_g      => Target_g,
            Initiator_g   => Initiator_g,
            Passthrough_g => Passthrough_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            S_Pkt_TData  => S_Pkt_TData,
            S_Pkt_TLast  => S_Pkt_TLast,
            S_Pkt_TValid => S_Pkt_TValid,
            S_Pkt_TReady => S_Pkt_TReady,
            M_Tgt_TData  => TgtCmdData,
            M_Tgt_TLast  => TgtCmdLast,
            M_Tgt_TValid => TgtCmdValid,
            M_Tgt_TReady => TgtCmdReady,
            M_Ini_TData  => IniRepData,
            M_Ini_TLast  => IniRepLast,
            M_Ini_TValid => IniRepValid,
            M_Ini_TReady => IniRepReady,
            M_Usr_TData  => M_User_TData,
            M_Usr_TLast  => M_User_TLast,
            M_Usr_TValid => M_User_TValid,
            M_Usr_TReady => UsrRxReady,
            Evt_User     => PktUser,
            Evt_Discard  => PktDiscard,
            Evt_CmdRx    => PktCmdRx
        );

    UsrRxReady <= M_User_TReady when Passthrough_g else '1';

    -- CO-2: packet multiplexer
    UsrTxValid <= S_User_TValid when Passthrough_g else '0';

    i_mux : entity work.omap_core_mux
        port map (
            Clk          => Clk,
            Rst          => Rst,
            S_Tgt_TData  => TgtRepData,
            S_Tgt_TLast  => TgtRepLast,
            S_Tgt_TValid => TgtRepValid,
            S_Tgt_TReady => TgtRepReady,
            S_Ini_TData  => IniCmdData,
            S_Ini_TLast  => IniCmdLast,
            S_Ini_TValid => IniCmdValid,
            S_Ini_TReady => IniCmdReady,
            S_Usr_TData  => S_User_TData,
            S_Usr_TLast  => S_User_TLast,
            S_Usr_TValid => UsrTxValid,
            S_Usr_TReady => S_User_TReady,
            M_Pkt_TData  => M_Pkt_TData,
            M_Pkt_TLast  => M_Pkt_TLast,
            M_Pkt_TValid => M_Pkt_TValid,
            M_Pkt_TReady => M_Pkt_TReady
        );

    -- Target
    g_target : if Target_g generate

        i_target : entity work.omap_target
            generic map (
                AxiAddrWidth_g => AxiAddrWidth_g,
                AxiDataWidth_g => AxiDataWidth_g,
                AxiMaxBeats_g  => AxiMaxBeats_g,
                BufferBytes_g  => BufferBytes_g,
                ChunkBytes_g   => ChunkBytes_g,
                Windows_g      => Windows_g,
                ExtAuth_g      => ExtAuth_g
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                S_Cmd_TData    => TgtCmdData,
                S_Cmd_TLast    => TgtCmdLast,
                S_Cmd_TValid   => TgtCmdValid,
                S_Cmd_TReady   => TgtCmdReady,
                M_Rep_TData    => TgtRepData,
                M_Rep_TLast    => TgtRepLast,
                M_Rep_TValid   => TgtRepValid,
                M_Rep_TReady   => TgtRepReady,
                Cfg_La0        => CfgLa0,
                Cfg_La0En      => CfgLa0En,
                Cfg_La1        => CfgLa1,
                Cfg_La1En      => CfgLa1En,
                Cfg_DefLaEn    => CfgDefLaEn,
                Cfg_Key        => CfgKey,
                Cfg_KeyEn      => CfgKeyEn,
                Cfg_Win        => CfgWin(0 to Windows_g - 1),
                Auth_Valid     => Auth_Valid,
                Auth_Tla       => Auth_Tla,
                Auth_Instr     => Auth_Instr,
                Auth_Key       => Auth_Key,
                Auth_Ila       => Auth_Ila,
                Auth_Tid       => Auth_Tid,
                Auth_Addr      => Auth_Addr,
                Auth_Len       => Auth_Len,
                Auth_RspValid  => Auth_RspValid,
                Auth_RspAccept => Auth_RspAccept,
                Ind_Valid      => IndValid,
                Ind_Tla        => Ind_Tla,
                Ind_Instr      => IndInstr,
                Ind_Ila        => IndIla,
                Ind_Tid        => IndTid,
                Ind_Addr       => IndAddr,
                Ind_Len        => Ind_Len,
                Ind_Status     => IndStatus,
                Ind_Replied    => IndReplied,
                Evt_HdrCrc     => TgtHdrCrc,
                Evt_HdrShort   => TgtHdrShort,
                Evt_ReplyRx    => TgtReplyRx,
                Evt_RepSent    => TgtRepSent,
                Ecc_Sec        => EccSec,
                Ecc_Ded        => EccDed,
                ErrInj_Valid   => InjValid,
                ErrInj_Double  => InjDouble,
                M_Axi_AwAddr   => M_Axi_AwAddr,
                M_Axi_AwLen    => M_Axi_AwLen,
                M_Axi_AwSize   => M_Axi_AwSize,
                M_Axi_AwBurst  => M_Axi_AwBurst,
                M_Axi_AwLock   => M_Axi_AwLock,
                M_Axi_AwCache  => M_Axi_AwCache,
                M_Axi_AwProt   => M_Axi_AwProt,
                M_Axi_AwValid  => M_Axi_AwValid,
                M_Axi_AwReady  => M_Axi_AwReady,
                M_Axi_WData    => M_Axi_WData,
                M_Axi_WStrb    => M_Axi_WStrb,
                M_Axi_WLast    => M_Axi_WLast,
                M_Axi_WValid   => M_Axi_WValid,
                M_Axi_WReady   => M_Axi_WReady,
                M_Axi_BResp    => M_Axi_BResp,
                M_Axi_BValid   => M_Axi_BValid,
                M_Axi_BReady   => M_Axi_BReady,
                M_Axi_ArAddr   => M_Axi_ArAddr,
                M_Axi_ArLen    => M_Axi_ArLen,
                M_Axi_ArSize   => M_Axi_ArSize,
                M_Axi_ArBurst  => M_Axi_ArBurst,
                M_Axi_ArLock   => M_Axi_ArLock,
                M_Axi_ArCache  => M_Axi_ArCache,
                M_Axi_ArProt   => M_Axi_ArProt,
                M_Axi_ArValid  => M_Axi_ArValid,
                M_Axi_ArReady  => M_Axi_ArReady,
                M_Axi_RData    => M_Axi_RData,
                M_Axi_RResp    => M_Axi_RResp,
                M_Axi_RLast    => M_Axi_RLast,
                M_Axi_RValid   => M_Axi_RValid,
                M_Axi_RReady   => M_Axi_RReady
            );

    end generate;

    g_no_target : if not Target_g generate
        TgtCmdReady   <= '1';
        IndValid      <= '0';
        IndInstr      <= (others => '0');
        IndIla        <= (others => '0');
        IndTid        <= (others => '0');
        IndAddr       <= (others => '0');
        IndStatus     <= (others => '0');
        IndReplied    <= '0';
        TgtHdrCrc     <= '0';
        TgtHdrShort   <= '0';
        TgtReplyRx    <= '0';
        TgtRepSent    <= '0';
        EccSec        <= (others => '0');
        EccDed        <= (others => '0');
        TgtRepData    <= (others => '0');
        TgtRepLast    <= '0';
        TgtRepValid   <= '0';
        Auth_Valid    <= '0';
        Auth_Tla      <= (others => '0');
        Auth_Instr    <= (others => '0');
        Auth_Key      <= (others => '0');
        Auth_Ila      <= (others => '0');
        Auth_Tid      <= (others => '0');
        Auth_Addr     <= (others => '0');
        Auth_Len      <= (others => '0');
        Ind_Tla       <= (others => '0');
        Ind_Len       <= (others => '0');
        M_Axi_AwAddr  <= (others => '0');
        M_Axi_AwLen   <= (others => '0');
        M_Axi_AwSize  <= (others => '0');
        M_Axi_AwBurst <= (others => '0');
        M_Axi_AwLock  <= '0';
        M_Axi_AwCache <= (others => '0');
        M_Axi_AwProt  <= (others => '0');
        M_Axi_AwValid <= '0';
        M_Axi_WData   <= (others => '0');
        M_Axi_WStrb   <= (others => '0');
        M_Axi_WLast   <= '0';
        M_Axi_WValid  <= '0';
        M_Axi_BReady  <= '0';
        M_Axi_ArAddr  <= (others => '0');
        M_Axi_ArLen   <= (others => '0');
        M_Axi_ArSize  <= (others => '0');
        M_Axi_ArBurst <= (others => '0');
        M_Axi_ArLock  <= '0';
        M_Axi_ArCache <= (others => '0');
        M_Axi_ArProt  <= (others => '0');
        M_Axi_ArValid <= '0';
        M_Axi_RReady  <= '0';
    end generate;

    Ind_Valid   <= IndValid;
    Ind_Instr   <= IndInstr;
    Ind_Ila     <= IndIla;
    Ind_Tid     <= IndTid;
    Ind_Addr    <= IndAddr;
    Ind_Status  <= IndStatus;
    Ind_Replied <= IndReplied;

    -- Initiator
    g_initiator : if Initiator_g generate

        i_initiator : entity work.omap_initiator
            generic map (
                TgtAddrBytes_g => TgtAddrBytes_g,
                Transactions_g => Transactions_g
            )
            port map (
                Clk                => Clk,
                Rst                => Rst,
                Cfg_TickCycles     => CfgTick,
                Cfg_Timeout        => CfgTimeout,
                S_Req_Valid        => S_Req_Valid,
                S_Req_Ready        => S_Req_Ready,
                S_Req_Code         => S_Req_Code,
                S_Req_TgtAddr      => S_Req_TgtAddr,
                S_Req_TgtAddrLen   => S_Req_TgtAddrLen,
                S_Req_Tla          => S_Req_Tla,
                S_Req_Key          => S_Req_Key,
                S_Req_ReplyAddr    => S_Req_ReplyAddr,
                S_Req_ReplyAddrLen => S_Req_ReplyAddrLen,
                S_Req_Ila          => S_Req_Ila,
                S_Req_Tid          => S_Req_Tid,
                S_Req_Addr         => S_Req_Addr,
                S_Req_Len          => S_Req_Len,
                S_Data_TData       => S_ReqData_TData,
                S_Data_TValid      => S_ReqData_TValid,
                S_Data_TReady      => S_ReqData_TReady,
                M_Conf_Valid       => M_Conf_Valid,
                M_Conf_Ready       => M_Conf_Ready,
                M_Conf_Tid         => M_Conf_Tid,
                M_Conf_Instr       => M_Conf_Instr,
                M_Conf_Status      => M_Conf_Status,
                M_Conf_Len         => M_Conf_Len,
                M_Conf_Error       => M_Conf_Error,
                M_Data_TData       => M_RepData_TData,
                M_Data_TLast       => M_RepData_TLast,
                M_Data_TValid      => M_RepData_TValid,
                M_Data_TReady      => M_RepData_TReady,
                M_Cmd_TData        => IniCmdData,
                M_Cmd_TLast        => IniCmdLast,
                M_Cmd_TValid       => IniCmdValid,
                M_Cmd_TReady       => IniCmdReady,
                S_Rep_TData        => IniRepData,
                S_Rep_TLast        => IniRepLast,
                S_Rep_TValid       => IniRepValid,
                S_Rep_TReady       => IniRepReady,
                Evt_CmdSent        => IniCmdSent,
                Evt_RepOk          => IniRepOk,
                Evt_HdrErr         => IniHdrErr,
                Evt_DataErr        => IniDataErr,
                Evt_Unexpected     => IniUnexpected,
                Evt_Timeout        => IniTimeout,
                Evt_TidBusy        => IniTidBusy,
                Stat_Open          => IniOpen
            );

    end generate;

    g_no_initiator : if not Initiator_g generate
        IniRepReady      <= '1';
        IniCmdSent       <= '0';
        IniRepOk         <= '0';
        IniHdrErr        <= '0';
        IniDataErr       <= '0';
        IniUnexpected    <= '0';
        IniTimeout       <= '0';
        IniTidBusy       <= '0';
        IniOpen          <= (others => '0');
        IniCmdData       <= (others => '0');
        IniCmdLast       <= '0';
        IniCmdValid      <= '0';
        S_Req_Ready      <= '0';
        S_ReqData_TReady <= '0';
        M_Conf_Valid     <= '0';
        M_Conf_Tid       <= (others => '0');
        M_Conf_Instr     <= (others => '0');
        M_Conf_Status    <= (others => '0');
        M_Conf_Len       <= (others => '0');
        M_Conf_Error     <= (others => '0');
        M_RepData_TData  <= (others => '0');
        M_RepData_TLast  <= '0';
        M_RepData_TValid <= '0';
    end generate;

    -- MG-1, MG-2: register file and EDAC monitor
    i_mib : entity work.omap_mib
        generic map (
            Target_g       => Target_g,
            Initiator_g    => Initiator_g,
            Passthrough_g  => Passthrough_g,
            ExtAuth_g      => ExtAuth_g and Target_g,
            Windows_g      => choose(Target_g, Windows_g, 0),
            Transactions_g => choose(Initiator_g, Transactions_g, 0),
            AxiDataWidth_g => AxiDataWidth_g,
            TgtAddrBytes_g => choose(Initiator_g, TgtAddrBytes_g, 0),
            BufferBytes_g  => BufferBytes_g,
            ChunkBytes_g   => ChunkBytes_g,
            La0_g          => La0_g,
            La1_g          => La1_g,
            DefLaEn_g      => DefLaEn_g,
            Key_g          => Key_g,
            TickCycles_g   => TickCycles_g,
            Timeout_g      => Timeout_g,
            WinInit_g      => WinInit_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Irq               => Irq,
            Cfg_La0           => CfgLa0,
            Cfg_La0En         => CfgLa0En,
            Cfg_La1           => CfgLa1,
            Cfg_La1En         => CfgLa1En,
            Cfg_DefLaEn       => CfgDefLaEn,
            Cfg_Key           => CfgKey,
            Cfg_KeyEn         => CfgKeyEn,
            Cfg_Win           => CfgWin,
            Cfg_TickCycles    => CfgTick,
            Cfg_Timeout       => CfgTimeout,
            Tgt_IndValid      => IndValid,
            Tgt_IndInstr      => IndInstr,
            Tgt_IndStatus     => IndStatus,
            Tgt_IndIla        => IndIla,
            Tgt_IndTid        => IndTid,
            Tgt_IndAddr       => IndAddr,
            Tgt_IndReplied    => IndReplied,
            Tgt_EvtHdrCrc     => TgtHdrCrc,
            Tgt_EvtHdrShort   => TgtHdrShort,
            Tgt_EvtReplyRx    => TgtReplyRx,
            Tgt_EvtRepSent    => TgtRepSent,
            Ini_EvtCmdSent    => IniCmdSent,
            Ini_EvtRepOk      => IniRepOk,
            Ini_EvtHdrErr     => IniHdrErr,
            Ini_EvtDataErr    => IniDataErr,
            Ini_EvtUnexpected => IniUnexpected,
            Ini_EvtTimeout    => IniTimeout,
            Ini_EvtTidBusy    => IniTidBusy,
            Ini_Open          => IniOpen,
            Pkt_EvtUser       => PktUser,
            Pkt_EvtDiscard    => PktDiscard,
            Pkt_EvtCmdRx      => PktCmdRx,
            Ecc_Sec           => EccSec,
            Ecc_Ded           => EccDed,
            Inj_Valid         => InjValid,
            Inj_Double        => InjDouble
        );

end architecture;
