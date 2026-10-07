---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the MIB: omap_mib at 100 MHz with generics that differ from the defaults, the
-- AXI4-Lite VVC and an observer of the configuration outputs and the injection commands.
--
-- Documentation: hdl/omap_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;

library work;
    use work.omap_pkg.all;
    use work.omap_target_tb_pkg.all;
    use work.omap_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_mib_th is
    port (
        Clk    : out   std_logic;
        Rst    : in    std_logic;
        MibIn  : in    MibIn_t;
        MibOut : out   MibOut_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_mib_th is

    -- Window 0 open, window 1 read and single-address accesses from 0x12_0000_1000 to 0x12_0000_1FFF, window 5
    -- (not implemented with Windows_g = 4) open
    constant WinInit_c : WinCfgArray_t(0 to WinMax_c - 1) := (
        0      => WinOpen_c,
        1      => tbWin("10001", x"1200001000", x"1200001FFF"),
        5      => WinOpen_c,
        others => WinDisabled_c
    );

    signal Clk_i     : std_logic := '0';
    signal ArAddr    : std_logic_vector(9 downto 0);
    signal ArValid   : std_logic;
    signal ArReady   : std_logic;
    signal AwAddr    : std_logic_vector(9 downto 0);
    signal AwValid   : std_logic;
    signal AwReady   : std_logic;
    signal WData     : std_logic_vector(31 downto 0);
    signal WStrb     : std_logic_vector(3 downto 0);
    signal WValid    : std_logic;
    signal WReady    : std_logic;
    signal BResp     : std_logic_vector(1 downto 0);
    signal BValid    : std_logic;
    signal BReady    : std_logic;
    signal RData     : std_logic_vector(31 downto 0);
    signal RResp     : std_logic_vector(1 downto 0);
    signal RValid    : std_logic;
    signal RReady    : std_logic;
    signal BValidD   : std_logic := '0';
    signal WrPulse   : std_logic;
    signal Ev        : std_logic_vector(13 downto 0);
    signal Cfg       : MibOut_t;
    signal InjValid  : std_logic_vector(2 downto 0);
    signal InjDouble : std_logic;

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk_i <= not Clk_i after 5 ns;
    Clk   <= Clk_i;

    -- The register file executes a write in the first cycle of BValid (olo_axi_lite_slave)
    BValidD <= BValid when rising_edge(Clk_i);
    WrPulse <= BValid and not BValidD and MibIn.OnWrite;

    p_ev : process (all) is
    begin
        Ev <= MibIn.Ev;
        if WrPulse = '1' then
            Ev(EvCmdSent_c) <= '1';
            Ev(EvRepOk_c)   <= '1';
        end if;
    end process;

    i_dut : entity work.omap_mib
        generic map (
            Target_g       => true,
            Initiator_g    => true,
            Passthrough_g  => false,
            ExtAuth_g      => true,
            Windows_g      => 4,
            Transactions_g => 8,
            AxiDataWidth_g => 64,
            TgtAddrBytes_g => 8,
            BufferBytes_g  => 512,
            ChunkBytes_g   => 64,
            La0_g          => x"42",
            La1_g          => x"43",
            DefLaEn_g      => '0',
            Key_g          => x"5A",
            TickCycles_g   => 199,
            Timeout_g      => 1000,
            WinInit_g      => WinInit_c
        )
        port map (
            Clk               => Clk_i,
            Rst               => Rst,
            S_AxiLite_ArAddr  => ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => WData,
            S_AxiLite_WStrb   => WStrb,
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => BResp,
            S_AxiLite_BValid  => BValid,
            S_AxiLite_BReady  => BReady,
            S_AxiLite_RData   => RData,
            S_AxiLite_RResp   => RResp,
            S_AxiLite_RValid  => RValid,
            S_AxiLite_RReady  => RReady,
            Irq               => Cfg.Irq,
            Cfg_La0           => Cfg.La0,
            Cfg_La0En         => Cfg.La0En,
            Cfg_La1           => Cfg.La1,
            Cfg_La1En         => Cfg.La1En,
            Cfg_DefLaEn       => Cfg.DefLaEn,
            Cfg_Key           => Cfg.Key,
            Cfg_KeyEn         => Cfg.KeyEn,
            Cfg_Win           => Cfg.Win,
            Cfg_TickCycles    => Cfg.TickCycles,
            Cfg_Timeout       => Cfg.Timeout,
            Tgt_IndValid      => MibIn.IndValid,
            Tgt_IndInstr      => MibIn.IndInstr,
            Tgt_IndStatus     => MibIn.IndStatus,
            Tgt_IndIla        => MibIn.IndIla,
            Tgt_IndTid        => MibIn.IndTid,
            Tgt_IndAddr       => MibIn.IndAddr,
            Tgt_IndReplied    => MibIn.IndReplied,
            Tgt_EvtHdrCrc     => Ev(EvHdrCrc_c),
            Tgt_EvtHdrShort   => Ev(EvHdrShort_c),
            Tgt_EvtReplyRx    => Ev(EvReplyRx_c),
            Tgt_EvtRepSent    => Ev(EvRepSent_c),
            Ini_EvtCmdSent    => Ev(EvCmdSent_c),
            Ini_EvtRepOk      => Ev(EvRepOk_c),
            Ini_EvtHdrErr     => Ev(EvHdrErr_c),
            Ini_EvtDataErr    => Ev(EvDataErr_c),
            Ini_EvtUnexpected => Ev(EvUnexpected_c),
            Ini_EvtTimeout    => Ev(EvTimeout_c),
            Ini_EvtTidBusy    => Ev(EvTidBusy_c),
            Ini_Open          => MibIn.IniOpen,
            Pkt_EvtUser       => Ev(EvUser_c),
            Pkt_EvtDiscard    => Ev(EvDiscard_c),
            Pkt_EvtCmdRx      => Ev(EvCmdRx_c),
            Ecc_Sec           => MibIn.EccSec,
            Ecc_Ded           => MibIn.EccDed,
            Inj_Valid         => InjValid,
            Inj_Double        => InjDouble
        );

    i_axi : entity work.omap_tb_axilite_master
        generic map (
            InstanceIdx_g => Axi_c,
            AddrWidth_g   => 10
        )
        port map (
            Clk     => Clk_i,
            ArAddr  => ArAddr,
            ArValid => ArValid,
            ArReady => ArReady,
            AwAddr  => AwAddr,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            RData   => RData,
            RResp   => RResp,
            RValid  => RValid,
            RReady  => RReady
        );

    -- Observer of the injection commands
    p_obs : process (Clk_i) is
        variable Cnt_v    : Natural3_t := (others => 0);
        variable Double_v : std_logic  := '0';
    begin
        if rising_edge(Clk_i) then
            if Rst = '1' then
                Cnt_v := (others => 0);
            else

                for i in 0 to 2 loop
                    if InjValid(i) = '1' then
                        Cnt_v(i) := Cnt_v(i) + 1;
                        Double_v := InjDouble;
                    end if;
                end loop;

            end if;
        end if;
        MibOut.La0        <= Cfg.La0;
        MibOut.La0En      <= Cfg.La0En;
        MibOut.La1        <= Cfg.La1;
        MibOut.La1En      <= Cfg.La1En;
        MibOut.DefLaEn    <= Cfg.DefLaEn;
        MibOut.Key        <= Cfg.Key;
        MibOut.KeyEn      <= Cfg.KeyEn;
        MibOut.Win        <= Cfg.Win;
        MibOut.TickCycles <= Cfg.TickCycles;
        MibOut.Timeout    <= Cfg.Timeout;
        MibOut.Irq        <= Cfg.Irq;
        MibOut.CntInj     <= Cnt_v;
        MibOut.LastDouble <= Double_v;
    end process;

end architecture;
