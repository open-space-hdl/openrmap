---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register file of OpenRMAP (MG-1, MG-2): configuration of the Target and the Initiator, status,
-- error counters, event flags with interrupt and the EDAC monitor of the buffers, behind an AXI4-Lite
-- slave. The register map is generated from hdl/omap_mib/regs/omap_regs.yml.
--
-- Documentation: hdl/omap_mib/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.omap_pkg.all;
    use work.omap_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_mib is
    generic (
        Target_g       : boolean                          := true;
        Initiator_g    : boolean                          := true;
        Passthrough_g  : boolean                          := true;
        ExtAuth_g      : boolean                          := false;
        Windows_g      : natural range 0 to WinMax_c      := 4;
        Transactions_g : natural range 0 to 64            := 8;
        AxiDataWidth_g : positive                         := 32;
        TgtAddrBytes_g : natural range 0 to 16            := 8;
        BufferBytes_g  : positive range 1 to 65535        := 256;
        ChunkBytes_g   : positive range 1 to 65535        := 32;
        La0_g          : std_logic_vector(7 downto 0)     := x"FE";
        La1_g          : std_logic_vector(7 downto 0)     := x"FE";
        DefLaEn_g      : std_logic                        := '1';
        Key_g          : std_logic_vector(7 downto 0)     := x"00";
        TickCycles_g   : natural range 0 to 65535         := 99;
        Timeout_g      : natural range 0 to 65535         := 0;
        WinInit_g      : WinCfgArray_t(0 to WinMax_c - 1) := WinInitOpen_c
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- AXI4-Lite
        S_AxiLite_ArAddr  : in    std_logic_vector(9 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(9 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        Irq               : out   std_logic;
        -- Configuration
        Cfg_La0           : out   std_logic_vector(7 downto 0);
        Cfg_La0En         : out   std_logic;
        Cfg_La1           : out   std_logic_vector(7 downto 0);
        Cfg_La1En         : out   std_logic;
        Cfg_DefLaEn       : out   std_logic;
        Cfg_Key           : out   std_logic_vector(7 downto 0);
        Cfg_KeyEn         : out   std_logic;
        Cfg_Win           : out   WinCfgArray_t(0 to WinMax_c - 1);
        Cfg_TickCycles    : out   std_logic_vector(15 downto 0);
        Cfg_Timeout       : out   std_logic_vector(15 downto 0);
        -- Target
        Tgt_IndValid      : in    std_logic                     := '0';
        Tgt_IndInstr      : in    std_logic_vector(7 downto 0)  := (others => '0');
        Tgt_IndStatus     : in    std_logic_vector(7 downto 0)  := (others => '0');
        Tgt_IndIla        : in    std_logic_vector(7 downto 0)  := (others => '0');
        Tgt_IndTid        : in    std_logic_vector(15 downto 0) := (others => '0');
        Tgt_IndAddr       : in    std_logic_vector(39 downto 0) := (others => '0');
        Tgt_IndReplied    : in    std_logic                     := '0';
        Tgt_EvtHdrCrc     : in    std_logic                     := '0';
        Tgt_EvtHdrShort   : in    std_logic                     := '0';
        Tgt_EvtReplyRx    : in    std_logic                     := '0';
        Tgt_EvtRepSent    : in    std_logic                     := '0';
        -- Initiator
        Ini_EvtCmdSent    : in    std_logic                     := '0';
        Ini_EvtRepOk      : in    std_logic                     := '0';
        Ini_EvtHdrErr     : in    std_logic                     := '0';
        Ini_EvtDataErr    : in    std_logic                     := '0';
        Ini_EvtUnexpected : in    std_logic                     := '0';
        Ini_EvtTimeout    : in    std_logic                     := '0';
        Ini_EvtTidBusy    : in    std_logic                     := '0';
        Ini_Open          : in    std_logic_vector(7 downto 0)  := (others => '0');
        -- Packet routing
        Pkt_EvtUser       : in    std_logic                     := '0';
        Pkt_EvtDiscard    : in    std_logic                     := '0';
        Pkt_EvtCmdRx      : in    std_logic                     := '0';
        -- ECC of the buffers (0 write buffer, 1 write data of the AXI master, 2 read data of the AXI master)
        Ecc_Sec           : in    std_logic_vector(2 downto 0)  := (others => '0');
        Ecc_Ded           : in    std_logic_vector(2 downto 0)  := (others => '0');
        Inj_Valid         : out   std_logic_vector(2 downto 0);
        Inj_Double        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_mib is

    -- Counters, two per register: index 2 * register + 0 for bits 15:0, + 1 for bits 31:16
    constant CntTgtWrite_c   : natural := 0;
    constant CntTgtRead_c    : natural := 1;
    constant CntTgtRmw_c     : natural := 2;
    constant CntTgtReplies_c : natural := 3;
    constant CntHdrCrc_c     : natural := 4;
    constant CntHdrShort_c   : natural := 5;
    constant CntGeneral_c    : natural := 6;
    constant CntUnused_c     : natural := 7;
    constant CntKey_c        : natural := 8;
    constant CntDataCrc_c    : natural := 9;
    constant CntEarlyEop_c   : natural := 10;
    constant CntTooMuch_c    : natural := 11;
    constant CntEep_c        : natural := 12;
    constant CntOverrun_c    : natural := 13;
    constant CntNotAuth_c    : natural := 14;
    constant CntRmwLength_c  : natural := 15;
    constant CntTla_c        : natural := 16;
    constant CntReplyRx_c    : natural := 17;
    constant CntCmdSent_c    : natural := 18;
    constant CntRepOk_c      : natural := 19;
    constant CntHdrErr_c     : natural := 20;
    constant CntDataErr_c    : natural := 21;
    constant CntUnexp_c      : natural := 22;
    constant CntTimeout_c    : natural := 23;
    constant CntTidBusy_c    : natural := 24;
    constant CntCmdRx_c      : natural := 25;
    constant CntUser_c       : natural := 26;
    constant CntDiscard_c    : natural := 27;
    constant Counters_c      : natural := 28;

    -- Register of each counter pair
    type CntReg_t is array (0 to Counters_c / 2 - 1) of natural;

    constant CntReg_c : CntReg_t := (
        RegTgtCntOk_c, RegTgtCntOk2_c, RegTgtCntHdr_c, RegTgtCntErr1_c, RegTgtCntErr2_c, RegTgtCntErr3_c,
        RegTgtCntErr4_c, RegTgtCntErr5_c, RegTgtCntErr6_c, RegIniCnt1_c, RegIniCnt2_c, RegIniCnt3_c, RegIniCnt4_c,
        RegPktCnt_c
    );

    type Counter_t is array (0 to Counters_c - 1) of unsigned(15 downto 0);

    -- Product characteristics fixed by generics (GENERICS, BUFFERS)
    constant Windows_c      : std_logic_vector(3 downto 0)  := std_logic_vector(to_unsigned(Windows_g, 4));
    constant Transactions_c : std_logic_vector(7 downto 0)  := std_logic_vector(to_unsigned(Transactions_g, 8));
    constant WordBytes_c    : std_logic_vector(7 downto 0)  := std_logic_vector(to_unsigned(AxiDataWidth_g / 8, 8));
    constant TgtAddrBytes_c : std_logic_vector(4 downto 0)  := std_logic_vector(to_unsigned(TgtAddrBytes_g, 5));
    constant BufferBytes_c  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(BufferBytes_g, 16));
    constant ChunkBytes_c   : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(ChunkBytes_g, 16));

    type TwoProcess_r is record
        La0       : std_logic_vector(7 downto 0);
        La1       : std_logic_vector(7 downto 0);
        La0En     : std_logic;
        La1En     : std_logic;
        DefLaEn   : std_logic;
        Key       : std_logic_vector(7 downto 0);
        KeyEn     : std_logic;
        Win       : WinCfgArray_t(0 to WinMax_c - 1);
        Tick      : std_logic_vector(15 downto 0);
        Timeout   : std_logic_vector(15 downto 0);
        LastStat  : std_logic_vector(7 downto 0);
        LastInstr : std_logic_vector(7 downto 0);
        LastIla   : std_logic_vector(7 downto 0);
        LastRep   : std_logic;
        LastTid   : std_logic_vector(15 downto 0);
        LastAddr  : std_logic_vector(39 downto 0);
        Cnt       : Counter_t;
        Events    : std_logic_vector(8 downto 0);
        IrqEn     : std_logic_vector(8 downto 0);
        Irq       : std_logic;
        EccSelect : std_logic_vector(1 downto 0);
        EccClr    : std_logic;
        EccRdClr  : std_logic;
        InjValid  : std_logic_vector(2 downto 0);
        InjDouble : std_logic;
        RdValid   : std_logic;
        RdData    : std_logic_vector(31 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    signal RbAddr    : std_logic_vector(9 downto 0);
    signal RbWr      : std_logic;
    signal RbWrData  : std_logic_vector(31 downto 0);
    signal RbRd      : std_logic;
    signal EccSecCnt : std_logic_vector(15 downto 0);
    signal EccDedCnt : std_logic_vector(15 downto 0);
    signal EccDed    : std_logic_vector(2 downto 0);
    signal EvtSec    : std_logic;
    signal EvtDed    : std_logic;

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

begin

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Inc_v  : std_logic_vector(Counters_c - 1 downto 0);
        variable Addr_v : natural range 0 to 1023;
        variable Rd_v   : std_logic_vector(31 downto 0);
        variable W_v    : natural range 0 to WinMax_c - 1;
        variable Wr_v   : std_logic_vector(31 downto 0);
    begin
        v          := r;
        v.EccClr   := '0';
        v.EccRdClr := '0';
        v.InjValid := (others => '0');
        v.RdValid  := '0';
        Inc_v      := (others => '0');

        -- Register writes; a clear is applied before the events of the same cycle (MG-RF-05)
        Addr_v := to_integer(unsigned(RbAddr(9 downto 2) & "00"));
        Wr_v   := RbWrData;
        if RbWr = '1' then

            case Addr_v is

                when RegTgtLa_c =>
                    v.La0     := Wr_v(TgtLaLa0Hi_c downto TgtLaLa0Lo_c);
                    v.La1     := Wr_v(TgtLaLa1Hi_c downto TgtLaLa1Lo_c);
                    v.La0En   := Wr_v(TgtLaLa0En_c);
                    v.La1En   := Wr_v(TgtLaLa1En_c);
                    v.DefLaEn := Wr_v(TgtLaDefLaEn_c);

                when RegTgtKey_c =>
                    v.Key   := Wr_v(TgtKeyKeyHi_c downto TgtKeyKeyLo_c);
                    v.KeyEn := Wr_v(TgtKeyKeyEn_c);

                when RegIniTimeout_c =>
                    v.Tick    := Wr_v(IniTimeoutTickCyclesHi_c downto IniTimeoutTickCyclesLo_c);
                    v.Timeout := Wr_v(IniTimeoutTimeoutHi_c downto IniTimeoutTimeoutLo_c);

                when RegEvents_c =>
                    v.Events := r.Events and not Wr_v(8 downto 0);

                when RegIrqEn_c =>
                    v.IrqEn := Wr_v(IrqEnEnableHi_c downto IrqEnEnableLo_c);

                when RegEccStatus_c =>
                    v.EccClr := '1';

                when RegEccSelect_c =>
                    v.EccSelect := Wr_v(EccSelectChannelHi_c downto EccSelectChannelLo_c);

                when RegEccCount_c =>
                    v.EccRdClr := '1';

                when RegEccInject_c =>
                    if Wr_v(EccInjectSingle_c) = '1' or Wr_v(EccInjectDouble_c) = '1' then

                        for i in 0 to 2 loop
                            if to_integer(unsigned(Wr_v(EccInjectChannelHi_c downto EccInjectChannelLo_c))) = i then
                                v.InjValid(i) := '1';
                            end if;
                        end loop;

                        v.InjDouble := Wr_v(EccInjectDouble_c);
                    end if;

                when others =>

                    -- Counters: any write clears both counters of the register
                    for i in 0 to Counters_c / 2 - 1 loop
                        if Addr_v = CntReg_c(i) then
                            v.Cnt(2 * i)     := (others => '0');
                            v.Cnt(2 * i + 1) := (others => '0');
                        end if;
                    end loop;

                    -- Windows of the Target (architecture D8)
                    if Addr_v >= RegWindowBase_c and Addr_v < RegWindowBase_c + Windows_g * RegWindowStride_c then
                        W_v := (Addr_v - RegWindowBase_c) / RegWindowStride_c;
                        if (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinCtrlOfs_c then
                            v.Win(W_v).Enable             := Wr_v(WinCtrlEnable_c);
                            v.Win(W_v).Read               := Wr_v(WinCtrlRead_c);
                            v.Win(W_v).Write              := Wr_v(WinCtrlWrite_c);
                            v.Win(W_v).VerifiedOnly       := Wr_v(WinCtrlVerifiedOnly_c);
                            v.Win(W_v).Rmw                := Wr_v(WinCtrlRmw_c);
                            v.Win(W_v).Single             := Wr_v(WinCtrlSingle_c);
                            v.Win(W_v).Base(39 downto 32) := Wr_v(WinCtrlBaseExtHi_c downto WinCtrlBaseExtLo_c);
                            v.Win(W_v).Last(39 downto 32) := Wr_v(WinCtrlLastExtHi_c downto WinCtrlLastExtLo_c);
                        elsif (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinBaseOfs_c then
                            v.Win(W_v).Base(31 downto 0) := Wr_v;
                        elsif (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinLastOfs_c then
                            v.Win(W_v).Last(31 downto 0) := Wr_v;
                        end if;
                    end if;

            end case;

        end if;

        -- Last command of the Target with an intact header
        if Tgt_IndValid = '1' then
            v.LastStat  := Tgt_IndStatus;
            v.LastInstr := Tgt_IndInstr;
            v.LastIla   := Tgt_IndIla;
            v.LastRep   := Tgt_IndReplied;
            v.LastTid   := Tgt_IndTid;
            v.LastAddr  := Tgt_IndAddr;
        end if;

        -- Counted events: commands of the Target by status (ECSS 5.6) and by kind
        if Tgt_IndValid = '1' then

            case Tgt_IndStatus is

                when StatusOk_c =>
                    if cmdKind(cmdCode(Tgt_IndInstr)) = CmdWrite then
                        Inc_v(CntTgtWrite_c) := '1';
                    elsif cmdKind(cmdCode(Tgt_IndInstr)) = CmdRead then
                        Inc_v(CntTgtRead_c) := '1';
                    else
                        Inc_v(CntTgtRmw_c) := '1';
                    end if;

                when StatusGeneral_c =>
                    Inc_v(CntGeneral_c) := '1';

                when StatusUnused_c =>
                    Inc_v(CntUnused_c) := '1';

                when StatusKey_c =>
                    Inc_v(CntKey_c) := '1';

                when StatusDataCrc_c =>
                    Inc_v(CntDataCrc_c) := '1';

                when StatusEarlyEop_c =>
                    Inc_v(CntEarlyEop_c) := '1';

                when StatusTooMuch_c =>
                    Inc_v(CntTooMuch_c) := '1';

                when StatusEep_c =>
                    Inc_v(CntEep_c) := '1';

                when StatusVerifyOverrun_c =>
                    Inc_v(CntOverrun_c) := '1';

                when StatusNotAuth_c =>
                    Inc_v(CntNotAuth_c) := '1';

                when StatusRmwLength_c =>
                    Inc_v(CntRmwLength_c) := '1';

                when StatusTla_c =>
                    Inc_v(CntTla_c) := '1';

                when others =>
                    null;

            end case;

        end if;
        Inc_v(CntTgtReplies_c) := Tgt_EvtRepSent;
        Inc_v(CntHdrCrc_c)     := Tgt_EvtHdrCrc;
        Inc_v(CntHdrShort_c)   := Tgt_EvtHdrShort;
        Inc_v(CntReplyRx_c)    := Tgt_EvtReplyRx;
        Inc_v(CntCmdSent_c)    := Ini_EvtCmdSent;
        Inc_v(CntRepOk_c)      := Ini_EvtRepOk;
        Inc_v(CntHdrErr_c)     := Ini_EvtHdrErr;
        Inc_v(CntDataErr_c)    := Ini_EvtDataErr;
        Inc_v(CntUnexp_c)      := Ini_EvtUnexpected;
        Inc_v(CntTimeout_c)    := Ini_EvtTimeout;
        Inc_v(CntTidBusy_c)    := Ini_EvtTidBusy;
        Inc_v(CntCmdRx_c)      := Pkt_EvtCmdRx;
        Inc_v(CntUser_c)       := Pkt_EvtUser;
        Inc_v(CntDiscard_c)    := Pkt_EvtDiscard;

        -- Saturating counters
        for i in 0 to Counters_c - 1 loop
            if Inc_v(i) = '1' and v.Cnt(i) /= x"FFFF" then
                v.Cnt(i) := v.Cnt(i) + 1;
            end if;
        end loop;

        -- Event flags
        if Tgt_IndValid = '1' then
            if Tgt_IndStatus = StatusOk_c then
                v.Events(EventsTgtCmd_c) := '1';
            else
                v.Events(EventsTgtError_c) := '1';
            end if;
        end if;
        if Tgt_EvtHdrCrc = '1' or Tgt_EvtHdrShort = '1' or Tgt_EvtReplyRx = '1' then
            v.Events(EventsTgtDiscard_c) := '1';
        end if;
        if Ini_EvtRepOk = '1' then
            v.Events(EventsIniReply_c) := '1';
        end if;
        if Ini_EvtHdrErr = '1' or Ini_EvtDataErr = '1' or Ini_EvtUnexpected = '1' or Ini_EvtTidBusy = '1' then
            v.Events(EventsIniError_c) := '1';
        end if;
        if Ini_EvtTimeout = '1' then
            v.Events(EventsIniTimeout_c) := '1';
        end if;
        if EvtSec = '1' then
            v.Events(EventsEccSec_c) := '1';
        end if;
        if EvtDed = '1' then
            v.Events(EventsEccDed_c) := '1';
        end if;
        if Pkt_EvtDiscard = '1' or Pkt_EvtCmdRx = '1' then
            v.Events(EventsPktDiscard_c) := '1';
        end if;

        -- Interrupt
        v.Irq := toSl((r.Events and r.IrqEn) /= "000000000");

        -- Register reads: data one cycle after the request
        Addr_v := to_integer(unsigned(RbAddr(9 downto 2) & "00"));
        Rd_v   := (others => '0');

        case Addr_v is

            when RegId_c =>
                Rd_v := RegMapId_c;

            when RegGenerics_c =>
                Rd_v(GenericsTarget_c)                                         := toSl(Target_g);
                Rd_v(GenericsInitiator_c)                                      := toSl(Initiator_g);
                Rd_v(GenericsPassthrough_c)                                    := toSl(Passthrough_g);
                Rd_v(GenericsExtAuth_c)                                        := toSl(ExtAuth_g);
                Rd_v(GenericsWindowsHi_c downto GenericsWindowsLo_c)           := Windows_c;
                Rd_v(GenericsTransactionsHi_c downto GenericsTransactionsLo_c) := Transactions_c;
                Rd_v(GenericsWordBytesHi_c downto GenericsWordBytesLo_c)       := WordBytes_c;
                Rd_v(GenericsTgtAddrBytesHi_c downto GenericsTgtAddrBytesLo_c) := TgtAddrBytes_c;

            when RegBuffers_c =>
                Rd_v(BuffersVerifyBytesHi_c downto BuffersVerifyBytesLo_c) := BufferBytes_c;
                Rd_v(BuffersChunkBytesHi_c downto BuffersChunkBytesLo_c)   := ChunkBytes_c;

            when RegTgtLa_c =>
                Rd_v(TgtLaLa0Hi_c downto TgtLaLa0Lo_c) := r.La0;
                Rd_v(TgtLaLa1Hi_c downto TgtLaLa1Lo_c) := r.La1;
                Rd_v(TgtLaLa0En_c)                     := r.La0En;
                Rd_v(TgtLaLa1En_c)                     := r.La1En;
                Rd_v(TgtLaDefLaEn_c)                   := r.DefLaEn;

            when RegTgtKey_c =>
                Rd_v(TgtKeyKeyHi_c downto TgtKeyKeyLo_c) := r.Key;
                Rd_v(TgtKeyKeyEn_c)                      := r.KeyEn;

            when RegTgtLast_c =>
                Rd_v(TgtLastStatusHi_c downto TgtLastStatusLo_c) := r.LastStat;
                Rd_v(TgtLastInstrHi_c downto TgtLastInstrLo_c)   := r.LastInstr;
                Rd_v(TgtLastIlaHi_c downto TgtLastIlaLo_c)       := r.LastIla;
                Rd_v(TgtLastReplied_c)                           := r.LastRep;

            when RegTgtLastTid_c =>
                Rd_v(15 downto 0) := r.LastTid;

            when RegTgtLastAddr_c =>
                Rd_v := r.LastAddr(31 downto 0);

            when RegTgtLastAddrExt_c =>
                Rd_v(7 downto 0) := r.LastAddr(39 downto 32);

            when RegIniTimeout_c =>
                Rd_v(IniTimeoutTickCyclesHi_c downto IniTimeoutTickCyclesLo_c) := r.Tick;
                Rd_v(IniTimeoutTimeoutHi_c downto IniTimeoutTimeoutLo_c)       := r.Timeout;

            when RegIniStatus_c =>
                Rd_v(IniStatusOpenHi_c downto IniStatusOpenLo_c) := Ini_Open;

            when RegEvents_c =>
                Rd_v(8 downto 0) := r.Events;

            when RegIrqEn_c =>
                Rd_v(IrqEnEnableHi_c downto IrqEnEnableLo_c) := r.IrqEn;

            when RegIrqStatus_c =>
                Rd_v(IrqStatusIrq_c) := r.Irq;

            when RegEccStatus_c =>
                Rd_v(EccStatusDedHi_c downto EccStatusDedLo_c) := EccDed;

            when RegEccSelect_c =>
                Rd_v(EccSelectChannelHi_c downto EccSelectChannelLo_c) := r.EccSelect;

            when RegEccCount_c =>
                Rd_v := EccDedCnt & EccSecCnt;

            when others =>

                for i in 0 to Counters_c / 2 - 1 loop
                    if Addr_v = CntReg_c(i) then
                        Rd_v := std_logic_vector(r.Cnt(2 * i + 1)) & std_logic_vector(r.Cnt(2 * i));
                    end if;
                end loop;

                if Addr_v >= RegWindowBase_c and Addr_v < RegWindowBase_c + Windows_g * RegWindowStride_c then
                    W_v := (Addr_v - RegWindowBase_c) / RegWindowStride_c;
                    if (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinCtrlOfs_c then
                        Rd_v(WinCtrlEnable_c)                              := r.Win(W_v).Enable;
                        Rd_v(WinCtrlRead_c)                                := r.Win(W_v).Read;
                        Rd_v(WinCtrlWrite_c)                               := r.Win(W_v).Write;
                        Rd_v(WinCtrlVerifiedOnly_c)                        := r.Win(W_v).VerifiedOnly;
                        Rd_v(WinCtrlRmw_c)                                 := r.Win(W_v).Rmw;
                        Rd_v(WinCtrlSingle_c)                              := r.Win(W_v).Single;
                        Rd_v(WinCtrlBaseExtHi_c downto WinCtrlBaseExtLo_c) := r.Win(W_v).Base(39 downto 32);
                        Rd_v(WinCtrlLastExtHi_c downto WinCtrlLastExtLo_c) := r.Win(W_v).Last(39 downto 32);
                    elsif (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinBaseOfs_c then
                        Rd_v := r.Win(W_v).Base(31 downto 0);
                    elsif (Addr_v - RegWindowBase_c) mod RegWindowStride_c = RegWinLastOfs_c then
                        Rd_v := r.Win(W_v).Last(31 downto 0);
                    end if;
                end if;

        end case;

        if RbRd = '1' then
            v.RdValid := '1';
            v.RdData  := Rd_v;
        end if;

        r_next <= v;
    end process;

    -- Outputs
    Irq            <= r.Irq;
    Cfg_La0        <= r.La0;
    Cfg_La0En      <= r.La0En;
    Cfg_La1        <= r.La1;
    Cfg_La1En      <= r.La1En;
    Cfg_DefLaEn    <= r.DefLaEn;
    Cfg_Key        <= r.Key;
    Cfg_KeyEn      <= r.KeyEn;
    Cfg_Win        <= r.Win;
    Cfg_TickCycles <= r.Tick;
    Cfg_Timeout    <= r.Timeout;
    Inj_Valid      <= r.InjValid;
    Inj_Double     <= r.InjDouble;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.La0       <= La0_g;
                r.La1       <= La1_g;
                r.La0En     <= '1';
                r.La1En     <= '0';
                r.DefLaEn   <= DefLaEn_g;
                r.Key       <= Key_g;
                r.KeyEn     <= '1';
                r.Win       <= WinInit_g;
                r.Tick      <= std_logic_vector(to_unsigned(TickCycles_g, 16));
                r.Timeout   <= std_logic_vector(to_unsigned(Timeout_g, 16));
                r.Cnt       <= (others => (others => '0'));
                r.Events    <= (others => '0');
                r.IrqEn     <= (others => '0');
                r.Irq       <= '0';
                r.EccSelect <= (others => '0');
                r.EccClr    <= '0';
                r.EccRdClr  <= '0';
                r.InjValid  <= (others => '0');
                r.InjDouble <= '0';
                r.RdValid   <= '0';
                r.LastStat  <= (others => '0');
                r.LastInstr <= (others => '0');
                r.LastIla   <= (others => '0');
                r.LastRep   <= '0';
                r.LastTid   <= (others => '0');
                r.LastAddr  <= (others => '0');
            end if;
        end if;
    end process;

    -- MG-1: AXI4-Lite slave
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 10,
            AxiDataWidth_g => 32
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
            Rb_Addr           => RbAddr,
            Rb_Wr             => RbWr,
            Rb_WrData         => RbWrData,
            Rb_Rd             => RbRd,
            Rb_RdData         => r.RdData,
            Rb_RdValid        => r.RdValid
        );

    -- MG-2: EDAC monitor
    i_ecc : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g     => 3,
            CounterWidth_g => 16
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            Clr        => r.EccClr,
            In_EccSec  => Ecc_Sec,
            In_EccDed  => Ecc_Ded,
            DedSticky  => EccDed,
            Evt_Sec    => EvtSec,
            Evt_Ded    => EvtDed,
            Rd_Channel => r.EccSelect,
            Rd_Ena     => '1',
            Rd_Clr     => r.EccRdClr,
            Rd_SecCnt  => EccSecCnt,
            Rd_DedCnt  => EccDedCnt,
            Rd_Valid   => open
        );

end architecture;
