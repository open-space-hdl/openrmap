---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the RMAP Target: omap_target at 100 MHz with an AXI4-Stream VVC on the command
-- input, an AXI4-Stream VVC on the reply output, the AXI memory model (instance 0) on the AXI4
-- master, a responder on the external authorisation port and monitors of the indications and
-- events.
--
-- Documentation: hdl/omap_target/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;

library work;
    use work.omap_pkg.all;
    use work.omap_target_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_target_th is
    generic (
        AxiDataWidth_g : positive := 32;
        Windows_g      : natural  := 4;
        ExtAuth_g      : boolean  := false;
        BufferBytes_g  : positive := 256;
        ChunkBytes_g   : positive := 32
    );
    port (
        Clk : out   std_logic;
        Rst : in    std_logic;
        Cfg : in    TgtCfg_t;
        Obs : out   TgtObs_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_target_th is

    signal Clk_i : std_logic := '0';

    signal CmdData     : std_logic_vector(7 downto 0);
    signal CmdLast     : std_logic;
    signal CmdValid    : std_logic;
    signal CmdReady    : std_logic;
    signal RepData     : std_logic_vector(7 downto 0);
    signal RepLast     : std_logic;
    signal RepValid    : std_logic;
    signal RepReady    : std_logic;
    signal VvcCmdValid : std_logic;
    signal VvcCmdReady : std_logic;
    signal VvcRepValid : std_logic;
    signal VvcRepReady : std_logic;

    signal AuthValid     : std_logic;
    signal AuthInstr     : std_logic_vector(7 downto 0);
    signal AuthAddr      : std_logic_vector(39 downto 0);
    signal AuthLen       : std_logic_vector(23 downto 0);
    signal AuthRspValid  : std_logic := '0';
    signal AuthRspAccept : std_logic := '0';

    signal IndValid   : std_logic;
    signal IndTla     : std_logic_vector(7 downto 0);
    signal IndInstr   : std_logic_vector(7 downto 0);
    signal IndIla     : std_logic_vector(7 downto 0);
    signal IndTid     : std_logic_vector(15 downto 0);
    signal IndAddr    : std_logic_vector(39 downto 0);
    signal IndLen     : std_logic_vector(23 downto 0);
    signal IndStatus  : std_logic_vector(7 downto 0);
    signal IndReplied : std_logic;
    signal EvtHdrCrc  : std_logic;
    signal EvtShort   : std_logic;
    signal EvtReplyRx : std_logic;
    signal EvtSent    : std_logic;
    signal EccSec     : std_logic_vector(2 downto 0);
    signal EccDed     : std_logic_vector(2 downto 0);

    signal AwAddr  : std_logic_vector(31 downto 0);
    signal AwLen   : std_logic_vector(7 downto 0);
    signal AwSize  : std_logic_vector(2 downto 0);
    signal AwBurst : std_logic_vector(1 downto 0);
    signal AwValid : std_logic;
    signal AwReady : std_logic;
    signal WData   : std_logic_vector(AxiDataWidth_g - 1 downto 0);
    signal WStrb   : std_logic_vector(AxiDataWidth_g / 8 - 1 downto 0);
    signal WLast   : std_logic;
    signal WValid  : std_logic;
    signal WReady  : std_logic;
    signal BResp   : std_logic_vector(1 downto 0);
    signal BValid  : std_logic;
    signal BReady  : std_logic;
    signal ArAddr  : std_logic_vector(31 downto 0);
    signal ArLen   : std_logic_vector(7 downto 0);
    signal ArSize  : std_logic_vector(2 downto 0);
    signal ArBurst : std_logic_vector(1 downto 0);
    signal ArValid : std_logic;
    signal ArReady : std_logic;
    signal RData   : std_logic_vector(AxiDataWidth_g - 1 downto 0);
    signal RResp   : std_logic_vector(1 downto 0);
    signal RLast   : std_logic;
    signal RValid  : std_logic;
    signal RReady  : std_logic;

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk_i <= not Clk_i after 5 ns;
    Clk   <= Clk_i;

    i_dut : entity work.omap_target
        generic map (
            AxiAddrWidth_g => 32,
            AxiDataWidth_g => AxiDataWidth_g,
            AxiMaxBeats_g  => 16,
            BufferBytes_g  => BufferBytes_g,
            ChunkBytes_g   => ChunkBytes_g,
            Windows_g      => Windows_g,
            ExtAuth_g      => ExtAuth_g
        )
        port map (
            Clk            => Clk_i,
            Rst            => Rst,
            S_Cmd_TData    => CmdData,
            S_Cmd_TLast    => CmdLast,
            S_Cmd_TValid   => CmdValid,
            S_Cmd_TReady   => CmdReady,
            M_Rep_TData    => RepData,
            M_Rep_TLast    => RepLast,
            M_Rep_TValid   => RepValid,
            M_Rep_TReady   => RepReady,
            Cfg_La0        => Cfg.La0,
            Cfg_La0En      => Cfg.La0En,
            Cfg_La1        => Cfg.La1,
            Cfg_La1En      => Cfg.La1En,
            Cfg_DefLaEn    => Cfg.DefLaEn,
            Cfg_Key        => Cfg.Key,
            Cfg_KeyEn      => Cfg.KeyEn,
            Cfg_Win        => Cfg.Win(0 to Windows_g - 1),
            Auth_Valid     => AuthValid,
            Auth_Instr     => AuthInstr,
            Auth_Addr      => AuthAddr,
            Auth_Len       => AuthLen,
            Auth_RspValid  => AuthRspValid,
            Auth_RspAccept => AuthRspAccept,
            Ind_Valid      => IndValid,
            Ind_Tla        => IndTla,
            Ind_Instr      => IndInstr,
            Ind_Ila        => IndIla,
            Ind_Tid        => IndTid,
            Ind_Addr       => IndAddr,
            Ind_Len        => IndLen,
            Ind_Status     => IndStatus,
            Ind_Replied    => IndReplied,
            Evt_HdrCrc     => EvtHdrCrc,
            Evt_HdrShort   => EvtShort,
            Evt_ReplyRx    => EvtReplyRx,
            Evt_RepSent    => EvtSent,
            Ecc_Sec        => EccSec,
            Ecc_Ded        => EccDed,
            ErrInj_Valid   => Cfg.ErrInj,
            ErrInj_Double  => Cfg.ErrDouble,
            M_Axi_AwAddr   => AwAddr,
            M_Axi_AwLen    => AwLen,
            M_Axi_AwSize   => AwSize,
            M_Axi_AwBurst  => AwBurst,
            M_Axi_AwValid  => AwValid,
            M_Axi_AwReady  => AwReady,
            M_Axi_WData    => WData,
            M_Axi_WStrb    => WStrb,
            M_Axi_WLast    => WLast,
            M_Axi_WValid   => WValid,
            M_Axi_WReady   => WReady,
            M_Axi_BResp    => BResp,
            M_Axi_BValid   => BValid,
            M_Axi_BReady   => BReady,
            M_Axi_ArAddr   => ArAddr,
            M_Axi_ArLen    => ArLen,
            M_Axi_ArSize   => ArSize,
            M_Axi_ArBurst  => ArBurst,
            M_Axi_ArValid  => ArValid,
            M_Axi_ArReady  => ArReady,
            M_Axi_RData    => RData,
            M_Axi_RResp    => RResp,
            M_Axi_RLast    => RLast,
            M_Axi_RValid   => RValid,
            M_Axi_RReady   => RReady
        );

    i_cmd_vvc : entity work.omap_tb_axis_master
        generic map (
            InstanceIdx_g => VvcCmd_c,
            DataWidth_g   => 8
        )
        port map (
            Clk       => Clk_i,
            Out_Data  => CmdData,
            Out_Last  => CmdLast,
            Out_Valid => VvcCmdValid,
            Out_Ready => VvcCmdReady
        );

    -- Drop modes for the reset tests
    CmdValid    <= VvcCmdValid and not Cfg.DropCmd;
    VvcCmdReady <= '1' when Cfg.DropCmd = '1' else CmdReady;
    VvcRepValid <= RepValid and not Cfg.DropRep;
    RepReady    <= '1' when Cfg.DropRep = '1' else VvcRepReady;

    i_rep_vvc : entity work.omap_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcRep_c,
            DataWidth_g   => 8
        )
        port map (
            Clk      => Clk_i,
            In_Data  => RepData,
            In_Last  => RepLast,
            In_Valid => VvcRepValid,
            In_Ready => VvcRepReady
        );

    i_ram : entity work.omap_tb_axi_ram
        generic map (
            Index_g     => 0,
            AddrWidth_g => 32,
            DataWidth_g => AxiDataWidth_g
        )
        port map (
            Clk     => Clk_i,
            Rst     => Rst,
            AwAddr  => AwAddr,
            AwLen   => AwLen,
            AwSize  => AwSize,
            AwBurst => AwBurst,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WLast   => WLast,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            ArAddr  => ArAddr,
            ArLen   => ArLen,
            ArSize  => ArSize,
            ArBurst => ArBurst,
            ArValid => ArValid,
            ArReady => ArReady,
            RData   => RData,
            RResp   => RResp,
            RLast   => RLast,
            RValid  => RValid,
            RReady  => RReady
        );

    -- External authorisation: answers every request after AuthDelay cycles
    p_auth : process is
    begin
        AuthRspValid <= '0';
        wait until rising_edge(Clk_i) and AuthValid = '1';

        for i in 1 to Cfg.AuthDelay loop
            wait until rising_edge(Clk_i);
        end loop;

        AuthRspValid  <= '1';
        AuthRspAccept <= Cfg.AuthAccept;
        wait until rising_edge(Clk_i);
        AuthRspValid  <= '0';
        wait until rising_edge(Clk_i);
    end process;

    -- Monitors
    p_obs : process (Clk_i) is
        variable Obs_v      : TgtObs_t  := (
                                             IndCnt      => 0,
                                            IndTla      => x"00",
                                            IndInstr    => x"00",
                                            IndIla      => x"00",
                                            IndTid      => x"0000",
                                            IndAddr     => (others => '0'),
                                             IndLen      => (others => '0'),
                                             IndStatus   => x"00",
                                            IndReplied  => '0',
                                            HdrCrcCnt   => 0,
                                            HdrShortCnt => 0,
                                            ReplyRxCnt  => 0,
                                            RepSentCnt  => 0,
                                            AuthCnt     => 0,
                                            AuthInstr   => x"00",
                                            AuthAddr    => (others => '0'),
                                             AuthLen     => (others => '0'),
                                             SecCnt      => 0,
                                            DedCnt      => 0,
                                            RepValid    => '0'
                                        );
        variable LastAuth_v : std_logic := '0';
    begin
        if rising_edge(Clk_i) then
            if IndValid = '1' then
                Obs_v.IndCnt     := Obs_v.IndCnt + 1;
                Obs_v.IndTla     := IndTla;
                Obs_v.IndInstr   := IndInstr;
                Obs_v.IndIla     := IndIla;
                Obs_v.IndTid     := IndTid;
                Obs_v.IndAddr    := IndAddr;
                Obs_v.IndLen     := IndLen;
                Obs_v.IndStatus  := IndStatus;
                Obs_v.IndReplied := IndReplied;
            end if;
            if EvtHdrCrc = '1' then
                Obs_v.HdrCrcCnt := Obs_v.HdrCrcCnt + 1;
            end if;
            if EvtShort = '1' then
                Obs_v.HdrShortCnt := Obs_v.HdrShortCnt + 1;
            end if;
            if EvtReplyRx = '1' then
                Obs_v.ReplyRxCnt := Obs_v.ReplyRxCnt + 1;
            end if;
            if EvtSent = '1' then
                Obs_v.RepSentCnt := Obs_v.RepSentCnt + 1;
            end if;
            if AuthValid = '1' and LastAuth_v = '0' then
                Obs_v.AuthCnt   := Obs_v.AuthCnt + 1;
                Obs_v.AuthInstr := AuthInstr;
                Obs_v.AuthAddr  := AuthAddr;
                Obs_v.AuthLen   := AuthLen;
            end if;
            LastAuth_v := AuthValid;

            for i in 0 to 2 loop
                if EccSec(i) = '1' then
                    Obs_v.SecCnt := Obs_v.SecCnt + 1;
                end if;
                if EccDed(i) = '1' then
                    Obs_v.DedCnt := Obs_v.DedCnt + 1;
                end if;
            end loop;

            Obs_v.RepValid := RepValid;
            Obs            <= Obs_v;
        end if;
    end process;

end architecture;
