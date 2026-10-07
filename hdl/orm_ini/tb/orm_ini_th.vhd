---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the RMAP initiator: orm_ini at 100 MHz with the request descriptor driven by the
-- test sequencer, AXI4-Stream VVCs on the write data, the commands, the replies and the reply data,
-- and a monitor that logs the confirmations and counts the events.
--
-- Documentation: hdl/orm_ini/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;

library work;
    use work.orm_ini_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_ini_th is
    generic (
        Transactions_g : natural := 4
    );
    port (
        Clk      : out   std_logic;
        Rst      : in    std_logic;
        Req      : in    IniReq_t;
        Cfg      : in    IniCfg_t;
        Obs      : out   IniObs_t;
        ReqReady : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of orm_ini_th is

    signal Clk_i : std_logic := '0';

    signal ReqReady_i   : std_logic;
    signal DataData     : std_logic_vector(7 downto 0);
    signal DataValid    : std_logic;
    signal DataReady    : std_logic;
    signal VvcDataValid : std_logic;
    signal VvcDataReady : std_logic;
    signal VvcCmdValid  : std_logic;
    signal VvcCmdReady  : std_logic;
    signal ConfValid    : std_logic;
    signal ConfTid      : std_logic_vector(15 downto 0);
    signal ConfInstr    : std_logic_vector(7 downto 0);
    signal ConfStatus   : std_logic_vector(7 downto 0);
    signal ConfLen      : std_logic_vector(23 downto 0);
    signal ConfError    : std_logic_vector(1 downto 0);
    signal RepDataData  : std_logic_vector(7 downto 0);
    signal RepDataLast  : std_logic;
    signal RepDataValid : std_logic;
    signal RepDataReady : std_logic;
    signal CmdData      : std_logic_vector(7 downto 0);
    signal CmdLast      : std_logic;
    signal CmdValid     : std_logic;
    signal CmdReady     : std_logic;
    signal RepData      : std_logic_vector(7 downto 0);
    signal RepLast      : std_logic;
    signal RepValid     : std_logic;
    signal RepReady     : std_logic;
    signal EvtSent      : std_logic;
    signal EvtOk        : std_logic;
    signal EvtHdr       : std_logic;
    signal EvtData      : std_logic;
    signal EvtUnexp     : std_logic;
    signal EvtTimeout   : std_logic;
    signal EvtTidBusy   : std_logic;
    signal StatOpen     : std_logic_vector(7 downto 0);

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk_i    <= not Clk_i after 5 ns;
    Clk      <= Clk_i;
    ReqReady <= ReqReady_i;

    i_dut : entity work.orm_ini
        generic map (
            TgtAddrBytes_g => 8,
            Transactions_g => Transactions_g
        )
        port map (
            Clk                => Clk_i,
            Rst                => Rst,
            Cfg_TickCycles     => Cfg.TickCycles,
            Cfg_Timeout        => Cfg.Timeout,
            S_Req_Valid        => Req.Valid,
            S_Req_Ready        => ReqReady_i,
            S_Req_Code         => Req.Code,
            S_Req_TgtAddr      => Req.TgtAddr,
            S_Req_TgtAddrLen   => std_logic_vector(to_unsigned(Req.TgtAddrLen, 5)),
            S_Req_Tla          => Req.Tla,
            S_Req_Key          => Req.Key,
            S_Req_ReplyAddr    => Req.ReplyAddr,
            S_Req_ReplyAddrLen => std_logic_vector(to_unsigned(Req.ReplyAddrLen, 4)),
            S_Req_Ila          => Req.Ila,
            S_Req_Tid          => Req.Tid,
            S_Req_Addr         => Req.Addr,
            S_Req_Len          => Req.Len,
            S_Data_TData       => DataData,
            S_Data_TValid      => DataValid,
            S_Data_TReady      => DataReady,
            M_Conf_Valid       => ConfValid,
            M_Conf_Ready       => Cfg.ConfReady,
            M_Conf_Tid         => ConfTid,
            M_Conf_Instr       => ConfInstr,
            M_Conf_Status      => ConfStatus,
            M_Conf_Len         => ConfLen,
            M_Conf_Error       => ConfError,
            M_Data_TData       => RepDataData,
            M_Data_TLast       => RepDataLast,
            M_Data_TValid      => RepDataValid,
            M_Data_TReady      => RepDataReady,
            M_Cmd_TData        => CmdData,
            M_Cmd_TLast        => CmdLast,
            M_Cmd_TValid       => CmdValid,
            M_Cmd_TReady       => CmdReady,
            S_Rep_TData        => RepData,
            S_Rep_TLast        => RepLast,
            S_Rep_TValid       => RepValid,
            S_Rep_TReady       => RepReady,
            Evt_CmdSent        => EvtSent,
            Evt_RepOk          => EvtOk,
            Evt_HdrErr         => EvtHdr,
            Evt_DataErr        => EvtData,
            Evt_Unexpected     => EvtUnexp,
            Evt_Timeout        => EvtTimeout,
            Evt_TidBusy        => EvtTidBusy,
            Stat_Open          => StatOpen
        );

    i_data_vvc : entity work.orm_tb_axis_master
        generic map (
            InstanceIdx_g => VvcData_c,
            DataWidth_g   => 8
        )
        port map (
            Clk       => Clk_i,
            Out_Data  => DataData,
            Out_Valid => VvcDataValid,
            Out_Ready => VvcDataReady
        );

    -- Drop modes for the reset test
    DataValid    <= VvcDataValid and not Cfg.DropData;
    VvcDataReady <= '1' when Cfg.DropData = '1' else DataReady;
    VvcCmdValid  <= CmdValid and not Cfg.DropCmd;
    CmdReady     <= '1' when Cfg.DropCmd = '1' else VvcCmdReady;

    i_cmd_vvc : entity work.orm_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcCmd_c,
            DataWidth_g   => 8
        )
        port map (
            Clk      => Clk_i,
            In_Data  => CmdData,
            In_Last  => CmdLast,
            In_Valid => VvcCmdValid,
            In_Ready => VvcCmdReady
        );

    i_rep_vvc : entity work.orm_tb_axis_master
        generic map (
            InstanceIdx_g => VvcRep_c,
            DataWidth_g   => 8
        )
        port map (
            Clk       => Clk_i,
            Out_Data  => RepData,
            Out_Last  => RepLast,
            Out_Valid => RepValid,
            Out_Ready => RepReady
        );

    i_repdata_vvc : entity work.orm_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcRepData_c,
            DataWidth_g   => 8
        )
        port map (
            Clk      => Clk_i,
            In_Data  => RepDataData,
            In_Last  => RepDataLast,
            In_Valid => RepDataValid,
            In_Ready => RepDataReady
        );

    -- Monitor
    p_obs : process (Clk_i) is
        variable Obs_v  : IniObs_t;
        variable Init_v : boolean := true;
    begin
        if rising_edge(Clk_i) then
            if Init_v then
                Obs_v.ConfCnt    := 0;
                Obs_v.CmdSentCnt := 0;
                Obs_v.RepOkCnt   := 0;
                Obs_v.HdrErrCnt  := 0;
                Obs_v.DataErrCnt := 0;
                Obs_v.UnexpCnt   := 0;
                Obs_v.TimeoutCnt := 0;
                Obs_v.TidBusyCnt := 0;
                Init_v           := false;
            end if;
            if ConfValid = '1' and Cfg.ConfReady = '1' then
                Obs_v.Conf(Obs_v.ConfCnt mod 64) := (Tid => ConfTid,
                                                     Instr => ConfInstr,
                                                     Status => ConfStatus,
                                                     Len => ConfLen,
                                                     Error => ConfError);
                Obs_v.ConfCnt                    := Obs_v.ConfCnt + 1;
            end if;
            if EvtSent = '1' then
                Obs_v.CmdSentCnt := Obs_v.CmdSentCnt + 1;
            end if;
            if EvtOk = '1' then
                Obs_v.RepOkCnt := Obs_v.RepOkCnt + 1;
            end if;
            if EvtHdr = '1' then
                Obs_v.HdrErrCnt := Obs_v.HdrErrCnt + 1;
            end if;
            if EvtData = '1' then
                Obs_v.DataErrCnt := Obs_v.DataErrCnt + 1;
            end if;
            if EvtUnexp = '1' then
                Obs_v.UnexpCnt := Obs_v.UnexpCnt + 1;
            end if;
            if EvtTimeout = '1' then
                Obs_v.TimeoutCnt := Obs_v.TimeoutCnt + 1;
            end if;
            if EvtTidBusy = '1' then
                Obs_v.TidBusyCnt := Obs_v.TidBusyCnt + 1;
            end if;
            Obs_v.ReqReady  := ReqReady_i;
            Obs_v.OpenCnt   := to_integer(unsigned(StatOpen));
            Obs_v.ConfValid := ConfValid;
            Obs             <= Obs_v;
        end if;
    end process;

end architecture;
