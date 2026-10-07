---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the core: two cores A and B at 100 MHz connected by a packet network model, each
-- with an AXI memory model, the AXI4-Lite VVC on its register file, AXI4-Stream VVCs on the write
-- data and the reply data of its initiator and on its user port, and a monitor of its confirmations.
-- The network passes the packets of each direction to the other core, optionally with a fault, or
-- captures them in an AXI4-Stream VVC.
--
-- Documentation: hdl/orm_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;

library work;
    use work.orm_pkg.all;
    use work.orm_ini_tb_pkg.all;
    use work.orm_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_core_th is
    generic (
        TargetA_g      : boolean := true;
        InitiatorA_g   : boolean := true;
        PassA_g        : boolean := true;
        TargetB_g      : boolean := true;
        InitiatorB_g   : boolean := true;
        PassB_g        : boolean := true;
        Transactions_g : natural := 1
    );
    port (
        Clk          : out   std_logic;
        Rst          : in    std_logic;
        Req          : in    IniReqArray_t;
        ReqReady     : out   std_logic_vector(0 to 1);
        NetCtrl      : in    NetCtrlArray_t;
        Obs          : out   CoreObsArray_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of orm_core_th is

    type Bool2_t is array (0 to 1) of boolean;

    type Nat2_t is array (0 to 1) of natural;

    constant Target_c    : Bool2_t := (TargetA_g, TargetB_g);
    constant Initiator_c : Bool2_t := (InitiatorA_g, InitiatorB_g);
    constant Pass_c      : Bool2_t := (PassA_g, PassB_g);
    constant DataWidth_c : Nat2_t  := (32, 64);

    signal Clk_i : std_logic := '0';

    -- Packet ports of the cores
    signal TxData  : ByteArray2_t;
    signal TxLast  : std_logic_vector(0 to 1);
    signal TxValid : std_logic_vector(0 to 1);
    signal TxReady : std_logic_vector(0 to 1);
    signal RxData  : ByteArray2_t;
    signal RxLast  : std_logic_vector(0 to 1);
    signal RxValid : std_logic_vector(0 to 1);
    signal RxReady : std_logic_vector(0 to 1);

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk_i <= not Clk_i after 5 ns;
    Clk   <= Clk_i;

    g_core : for c in 0 to 1 generate
        signal AwAddr       : std_logic_vector(31 downto 0);
        signal AwLen        : std_logic_vector(7 downto 0);
        signal AwSize       : std_logic_vector(2 downto 0);
        signal AwBurst      : std_logic_vector(1 downto 0);
        signal AwValid      : std_logic;
        signal AwReady      : std_logic;
        signal WData        : std_logic_vector(DataWidth_c(c) - 1 downto 0);
        signal WStrb        : std_logic_vector(DataWidth_c(c) / 8 - 1 downto 0);
        signal WLast        : std_logic;
        signal WValid       : std_logic;
        signal WReady       : std_logic;
        signal BResp        : std_logic_vector(1 downto 0);
        signal BValid       : std_logic;
        signal BReady       : std_logic;
        signal ArAddr       : std_logic_vector(31 downto 0);
        signal ArLen        : std_logic_vector(7 downto 0);
        signal ArSize       : std_logic_vector(2 downto 0);
        signal ArBurst      : std_logic_vector(1 downto 0);
        signal ArValid      : std_logic;
        signal ArReady      : std_logic;
        signal RData        : std_logic_vector(DataWidth_c(c) - 1 downto 0);
        signal RResp        : std_logic_vector(1 downto 0);
        signal RLast        : std_logic;
        signal RValid       : std_logic;
        signal RReady       : std_logic;
        signal LiteArAddr   : std_logic_vector(9 downto 0);
        signal LiteArValid  : std_logic;
        signal LiteArReady  : std_logic;
        signal LiteAwAddr   : std_logic_vector(9 downto 0);
        signal LiteAwValid  : std_logic;
        signal LiteAwReady  : std_logic;
        signal LiteWData    : std_logic_vector(31 downto 0);
        signal LiteWStrb    : std_logic_vector(3 downto 0);
        signal LiteWValid   : std_logic;
        signal LiteWReady   : std_logic;
        signal LiteBResp    : std_logic_vector(1 downto 0);
        signal LiteBValid   : std_logic;
        signal LiteBReady   : std_logic;
        signal LiteRData    : std_logic_vector(31 downto 0);
        signal LiteRResp    : std_logic_vector(1 downto 0);
        signal LiteRValid   : std_logic;
        signal LiteRReady   : std_logic;
        signal Irq          : std_logic;
        signal UsrRxData    : std_logic_vector(7 downto 0);
        signal UsrRxLast    : std_logic;
        signal UsrRxValid   : std_logic;
        signal UsrRxReady   : std_logic;
        signal UsrTxData    : std_logic_vector(7 downto 0);
        signal UsrTxLast    : std_logic;
        signal UsrTxValid   : std_logic;
        signal UsrTxReady   : std_logic;
        signal IndValid     : std_logic;
        signal IndStatus    : std_logic_vector(7 downto 0);
        signal DataData     : std_logic_vector(7 downto 0);
        signal DataValid    : std_logic;
        signal DataReady    : std_logic;
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
    begin

        i_core : entity work.orm_core
            generic map (
                Target_g       => Target_c(c),
                Initiator_g    => Initiator_c(c),
                Passthrough_g  => Pass_c(c),
                AxiAddrWidth_g => 32,
                AxiDataWidth_g => DataWidth_c(c),
                AxiMaxBeats_g  => 16,
                BufferBytes_g  => 256,
                ChunkBytes_g   => 32,
                Windows_g      => 4,
                ExtAuth_g      => false,
                TgtAddrBytes_g => 8,
                Transactions_g => Transactions_g,
                La0_g          => CoreLa_c(c),
                La1_g          => x"FE",
                DefLaEn_g      => '1',
                Key_g          => x"00",
                TickCycles_g   => 9,
                Timeout_g      => 200
            )
            port map (
                Clk                => Clk_i,
                Rst                => Rst,
                S_Pkt_TData        => RxData(c),
                S_Pkt_TLast        => RxLast(c),
                S_Pkt_TValid       => RxValid(c),
                S_Pkt_TReady       => RxReady(c),
                M_Pkt_TData        => TxData(c),
                M_Pkt_TLast        => TxLast(c),
                M_Pkt_TValid       => TxValid(c),
                M_Pkt_TReady       => TxReady(c),
                M_User_TData       => UsrRxData,
                M_User_TLast       => UsrRxLast,
                M_User_TValid      => UsrRxValid,
                M_User_TReady      => UsrRxReady,
                S_User_TData       => UsrTxData,
                S_User_TLast       => UsrTxLast,
                S_User_TValid      => UsrTxValid,
                S_User_TReady      => UsrTxReady,
                S_AxiLite_ArAddr   => LiteArAddr,
                S_AxiLite_ArValid  => LiteArValid,
                S_AxiLite_ArReady  => LiteArReady,
                S_AxiLite_AwAddr   => LiteAwAddr,
                S_AxiLite_AwValid  => LiteAwValid,
                S_AxiLite_AwReady  => LiteAwReady,
                S_AxiLite_WData    => LiteWData,
                S_AxiLite_WStrb    => LiteWStrb,
                S_AxiLite_WValid   => LiteWValid,
                S_AxiLite_WReady   => LiteWReady,
                S_AxiLite_BResp    => LiteBResp,
                S_AxiLite_BValid   => LiteBValid,
                S_AxiLite_BReady   => LiteBReady,
                S_AxiLite_RData    => LiteRData,
                S_AxiLite_RResp    => LiteRResp,
                S_AxiLite_RValid   => LiteRValid,
                S_AxiLite_RReady   => LiteRReady,
                Irq                => Irq,
                M_Axi_AwAddr       => AwAddr,
                M_Axi_AwLen        => AwLen,
                M_Axi_AwSize       => AwSize,
                M_Axi_AwBurst      => AwBurst,
                M_Axi_AwLock       => open,
                M_Axi_AwCache      => open,
                M_Axi_AwProt       => open,
                M_Axi_AwValid      => AwValid,
                M_Axi_AwReady      => AwReady,
                M_Axi_WData        => WData,
                M_Axi_WStrb        => WStrb,
                M_Axi_WLast        => WLast,
                M_Axi_WValid       => WValid,
                M_Axi_WReady       => WReady,
                M_Axi_BResp        => BResp,
                M_Axi_BValid       => BValid,
                M_Axi_BReady       => BReady,
                M_Axi_ArAddr       => ArAddr,
                M_Axi_ArLen        => ArLen,
                M_Axi_ArSize       => ArSize,
                M_Axi_ArBurst      => ArBurst,
                M_Axi_ArLock       => open,
                M_Axi_ArCache      => open,
                M_Axi_ArProt       => open,
                M_Axi_ArValid      => ArValid,
                M_Axi_ArReady      => ArReady,
                M_Axi_RData        => RData,
                M_Axi_RResp        => RResp,
                M_Axi_RLast        => RLast,
                M_Axi_RValid       => RValid,
                M_Axi_RReady       => RReady,
                Auth_Valid         => open,
                Auth_Tla           => open,
                Auth_Instr         => open,
                Auth_Key           => open,
                Auth_Ila           => open,
                Auth_Tid           => open,
                Auth_Addr          => open,
                Auth_Len           => open,
                Ind_Valid          => IndValid,
                Ind_Tla            => open,
                Ind_Instr          => open,
                Ind_Ila            => open,
                Ind_Tid            => open,
                Ind_Addr           => open,
                Ind_Len            => open,
                Ind_Status         => IndStatus,
                Ind_Replied        => open,
                S_Req_Valid        => Req(c).Valid,
                S_Req_Ready        => ReqReady(c),
                S_Req_Code         => Req(c).Code,
                S_Req_TgtAddr      => Req(c).TgtAddr,
                S_Req_TgtAddrLen   => std_logic_vector(to_unsigned(Req(c).TgtAddrLen, 5)),
                S_Req_Tla          => Req(c).Tla,
                S_Req_Key          => Req(c).Key,
                S_Req_ReplyAddr    => Req(c).ReplyAddr,
                S_Req_ReplyAddrLen => std_logic_vector(to_unsigned(Req(c).ReplyAddrLen, 4)),
                S_Req_Ila          => Req(c).Ila,
                S_Req_Tid          => Req(c).Tid,
                S_Req_Addr         => Req(c).Addr,
                S_Req_Len          => Req(c).Len,
                S_ReqData_TData    => DataData,
                S_ReqData_TValid   => DataValid,
                S_ReqData_TReady   => DataReady,
                M_Conf_Valid       => ConfValid,
                M_Conf_Ready       => '1',
                M_Conf_Tid         => ConfTid,
                M_Conf_Instr       => ConfInstr,
                M_Conf_Status      => ConfStatus,
                M_Conf_Len         => ConfLen,
                M_Conf_Error       => ConfError,
                M_RepData_TData    => RepDataData,
                M_RepData_TLast    => RepDataLast,
                M_RepData_TValid   => RepDataValid,
                M_RepData_TReady   => RepDataReady
            );

        i_ram : entity work.orm_tb_axi_ram
            generic map (
                Index_g     => c,
                AddrWidth_g => 32,
                DataWidth_g => DataWidth_c(c)
            )
            port map (
                Clk     => Clk_i,
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

        i_axilite : entity work.orm_tb_axilite_master
            generic map (
                InstanceIdx_g => c,
                AddrWidth_g   => 10
            )
            port map (
                Clk     => Clk_i,
                ArAddr  => LiteArAddr,
                ArValid => LiteArValid,
                ArReady => LiteArReady,
                AwAddr  => LiteAwAddr,
                AwValid => LiteAwValid,
                AwReady => LiteAwReady,
                WData   => LiteWData,
                WStrb   => LiteWStrb,
                WValid  => LiteWValid,
                WReady  => LiteWReady,
                BResp   => LiteBResp,
                BValid  => LiteBValid,
                BReady  => LiteBReady,
                RData   => LiteRData,
                RResp   => LiteRResp,
                RValid  => LiteRValid,
                RReady  => LiteRReady
            );

        i_reqdata_vvc : entity work.orm_tb_axis_master
            generic map (
                InstanceIdx_g => VvcCoReqData_c + c,
                DataWidth_g   => 8
            )
            port map (
                Clk       => Clk_i,
                Out_Data  => DataData,
                Out_Valid => DataValid,
                Out_Ready => DataReady
            );

        i_repdata_vvc : entity work.orm_tb_axis_slave
            generic map (
                InstanceIdx_g => VvcCoRepData_c + c,
                DataWidth_g   => 8
            )
            port map (
                Clk      => Clk_i,
                In_Data  => RepDataData,
                In_Last  => RepDataLast,
                In_Valid => RepDataValid,
                In_Ready => RepDataReady
            );

        i_usrtx_vvc : entity work.orm_tb_axis_master
            generic map (
                InstanceIdx_g => VvcCoUsrTx_c + c,
                DataWidth_g   => 8
            )
            port map (
                Clk       => Clk_i,
                Out_Data  => UsrTxData,
                Out_Last  => UsrTxLast,
                Out_Valid => UsrTxValid,
                Out_Ready => UsrTxReady
            );

        i_usrrx_vvc : entity work.orm_tb_axis_slave
            generic map (
                InstanceIdx_g => VvcCoUsrRx_c + c,
                DataWidth_g   => 8
            )
            port map (
                Clk      => Clk_i,
                In_Data  => UsrRxData,
                In_Last  => UsrRxLast,
                In_Valid => UsrRxValid,
                In_Ready => UsrRxReady
            );

        -- Monitor of the confirmations and the indications
        p_obs : process (Clk_i) is
            variable Obs_v  : CoreObs_t;
            variable Init_v : boolean := true;
        begin
            if rising_edge(Clk_i) then
                if Init_v then
                    Obs_v.ConfCnt   := 0;
                    Obs_v.IndCnt    := 0;
                    Obs_v.IndStatus := (others => '0');
                    Init_v          := false;
                end if;
                if ConfValid = '1' then
                    Obs_v.Conf(Obs_v.ConfCnt mod 64) := (Tid => ConfTid,
                                                         Instr => ConfInstr,
                                                         Status => ConfStatus,
                                                         Len => ConfLen,
                                                         Error => ConfError);
                    Obs_v.ConfCnt                    := Obs_v.ConfCnt + 1;
                end if;
                if IndValid = '1' then
                    Obs_v.IndCnt    := Obs_v.IndCnt + 1;
                    Obs_v.IndStatus := IndStatus;
                end if;
                Obs_v.ReqReady := ReqReady(c);
                Obs_v.Irq      := Irq;
                Obs(c)         <= Obs_v;
            end if;
        end process;

    end generate;

    -- Packet network model: direction d from core d to core 1 - d
    g_net : for d in 0 to 1 generate
        signal CapData  : std_logic_vector(7 downto 0);
        signal CapLast  : std_logic;
        signal CapValid : std_logic;
        signal CapReady : std_logic;
        signal Idx      : natural := 0;    -- Data character of the current packet
        signal Trunc    : std_logic := '0'; -- Rest of a truncated packet being dropped
    begin

        p_net : process (all) is
            variable Src_v : std_logic;
        begin
            CapData        <= TxData(d);
            CapLast        <= TxLast(d);
            CapValid       <= '0';
            RxData(1 - d)  <= TxData(d);
            RxLast(1 - d)  <= TxLast(d);
            RxValid(1 - d) <= '0';
            Src_v          := '0';
            if NetCtrl(d).Capture = '1' then
                CapValid <= TxValid(d);
                Src_v    := CapReady;
            elsif Trunc = '1' or NetCtrl(d).Fault = FaultDrop_c then
                Src_v := '1';
            elsif NetCtrl(d).Fault = FaultTruncate_c and Idx = NetCtrl(d).Idx and TxLast(d) = '0' then
                -- EEP instead of the character; the source is held until the EEP is taken
                RxData(1 - d)  <= x"01";
                RxLast(1 - d)  <= '1';
                RxValid(1 - d) <= TxValid(d);
            else
                if NetCtrl(d).Fault = FaultFlip_c and Idx = NetCtrl(d).Idx and TxLast(d) = '0' then
                    RxData(1 - d) <= TxData(d) xor x"10";
                end if;
                RxValid(1 - d) <= TxValid(d);
                Src_v          := RxReady(1 - d);
            end if;
            TxReady(d) <= Src_v;
        end process;

        p_idx : process (Clk_i) is
        begin
            if rising_edge(Clk_i) then
                if NetCtrl(d).Capture = '0' and NetCtrl(d).Fault = FaultTruncate_c and Trunc = '0' and Idx = NetCtrl(d).Idx
                   and TxLast(d) = '0' and TxValid(d) = '1' and RxReady(1 - d) = '1' then
                    Trunc <= '1';
                end if;
                if TxValid(d) = '1' and TxReady(d) = '1' then
                    if TxLast(d) = '1' then
                        Idx   <= 0;
                        Trunc <= '0';
                    else
                        Idx <= Idx + 1;
                    end if;
                end if;
                if Rst = '1' then
                    Idx   <= 0;
                    Trunc <= '0';
                end if;
            end if;
        end process;

        i_cap_vvc : entity work.orm_tb_axis_slave
            generic map (
                InstanceIdx_g => VvcCoCap_c + d,
                DataWidth_g   => 8
            )
            port map (
                Clk      => Clk_i,
                In_Data  => CapData,
                In_Last  => CapLast,
                In_Valid => CapValid,
                In_Ready => CapReady
            );

    end generate;

end architecture;
