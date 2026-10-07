---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the MIB: register map over AXI4-Lite, configuration outputs, status of the target
-- and the initiator, sticky flags, counters, interrupt, EDAC monitor and error injection.
--
-- Documentation: hdl/orm_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.orm_pkg.all;
    use work.orm_regs_pkg.all;
    use work.orm_tb_pkg.all;
    use work.orm_tgt_tb_pkg.all;
    use work.orm_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_mib_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of orm_mib_tb is

    signal Clk    : std_logic;
    signal Rst    : std_logic := '1';
    signal MibIn  : MibIn_t   := MibInInit_c;
    signal MibOut : MibOut_t;

    -- Registers of the counters
    type Natural14_t is array (0 to 13) of natural;

    constant CntRegs_c : Natural14_t := (
        RegTgtCntOk_c, RegTgtCntOk2_c, RegTgtCntHdr_c, RegTgtCntErr1_c, RegTgtCntErr2_c, RegTgtCntErr3_c,
        RegTgtCntErr4_c, RegTgtCntErr5_c, RegTgtCntErr6_c, RegIniCnt1_c, RegIniCnt2_c, RegIniCnt3_c, RegIniCnt4_c,
        RegPktCnt_c
    );

begin

    test_runner_watchdog(runner, 10 ms);

    p_main : process is
        variable Data_v : std_logic_vector(31 downto 0);

        procedure regWrite (
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(addr, 10), data, "write 0x" & to_hstring(to_unsigned(addr, 12)));
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        procedure regCheck (
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(addr, 10), data, msg);
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        -- Address of register reg of window n
        function win (
            n   : natural;
            reg : natural) return natural is
        begin
            return reg + n * RegWindowStride_c;
        end function;

        -- One-cycle pulse on event input n, count times
        procedure event (
            n     : natural;
            count : positive := 1) is
        begin

            for i in 1 to count loop
                wait until rising_edge(Clk);
                MibIn.Ev(n) <= '1';
                wait until rising_edge(Clk);
                MibIn.Ev(n) <= '0';
            end loop;

            wait for 50 ns;
        end procedure;

        -- Indication of a command of the target
        procedure ind (
            instr   : std_logic_vector(7 downto 0);
            status  : std_logic_vector(7 downto 0);
            replied : std_logic                     := '1';
            ila     : std_logic_vector(7 downto 0)  := x"FE";
            tid     : std_logic_vector(15 downto 0) := x"0000";
            addr    : std_logic_vector(39 downto 0) := x"0000000000") is
        begin
            wait until rising_edge(Clk);
            MibIn.IndValid   <= '1';
            MibIn.IndInstr   <= instr;
            MibIn.IndStatus  <= status;
            MibIn.IndReplied <= replied;
            MibIn.IndIla     <= ila;
            MibIn.IndTid     <= tid;
            MibIn.IndAddr    <= addr;
            wait until rising_edge(Clk);
            MibIn.IndValid   <= '0';
            wait for 50 ns;
        end procedure;

        -- ECC event: kind 0 SEC, 1 DED, in channel ch
        procedure eccEvent (
            ch   : natural;
            kind : natural) is
        begin
            wait until rising_edge(Clk);
            if kind = 0 then
                MibIn.EccSec(ch) <= '1';
            else
                MibIn.EccDed(ch) <= '1';
            end if;
            wait until rising_edge(Clk);
            MibIn.EccSec <= "000";
            MibIn.EccDed <= "000";
            wait for 50 ns;
        end procedure;

        -- Sets EVENTS bit n through its source
        procedure setEvent (n : natural) is
        begin

            case n is

                when EventsTgtError_c =>
                    ind(x"7C", StatusKey_c);

                when EventsTgtDiscard_c =>
                    event(EvHdrCrc_c);

                when EventsTgtCmd_c =>
                    ind(x"7C", StatusOk_c);

                when EventsIniReply_c =>
                    event(EvRepOk_c);

                when EventsIniError_c =>
                    event(EvHdrErr_c);

                when EventsIniTimeout_c =>
                    event(EvTimeout_c);

                when EventsEccSec_c =>
                    eccEvent(0, 0);

                when EventsEccDed_c =>
                    eccEvent(0, 1);

                when others =>
                    event(EvDiscard_c);

            end case;

        end procedure;

        procedure checkEvents (
            bits : std_logic_vector(8 downto 0);
            msg  : string) is
        begin
            regCheck(RegEvents_c, x"00000" & "000" & bits, msg);
            regWrite(RegEvents_c, x"000001FF");
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(AXILITE_VVCT, Axi_c, ALL_MESSAGES);

        while test_suite loop

            MibIn <= MibInInit_c;
            Rst   <= '1';
            wait for 100 ns;
            wait until rising_edge(Clk);
            Rst   <= '0';
            wait for 100 ns;

            if run("test_reset_values") then
                -- TC-MB-01
                regCheck(RegId_c, RegMapId_c, "ID");
                regCheck(RegGenerics_c, x"0808084B", "generics");
                regCheck(RegBuffers_c, x"00400200", "buffer sizes");
                regCheck(RegTgtLa_c, x"00014342", "logical addresses from the generics");
                regCheck(RegTgtKey_c, x"0000015A", "key from the generic");
                regCheck(RegTgtLast_c, x"00000000", "TGT_LAST");
                regCheck(RegTgtLastTid_c, x"00000000", "TGT_LAST_TID");
                regCheck(RegTgtLastAddr_c, x"00000000", "TGT_LAST_ADDR");
                regCheck(RegTgtLastAddrExt_c, x"00000000", "TGT_LAST_ADDR_EXT");

                for i in CntRegs_c'range loop
                    regCheck(CntRegs_c(i), x"00000000", "counter register " & to_string(i));
                end loop;

                regCheck(RegIniTimeout_c, x"03E800C7", "timeout and tick from the generics");
                regCheck(RegIniStatus_c, x"00000000", "INI_STATUS");
                regCheck(RegEvents_c, RegEventsReset_c, "EVENTS");
                regCheck(RegIrqEn_c, RegIrqEnReset_c, "IRQ_EN");
                regCheck(RegIrqStatus_c, x"00000000", "IRQ_STATUS");
                regCheck(RegEccStatus_c, RegEccStatusReset_c, "ECC_STATUS");
                regCheck(RegEccSelect_c, RegEccSelectReset_c, "ECC_SELECT");
                regCheck(RegEccCount_c, RegEccCountReset_c, "ECC_COUNT");
                regCheck(RegEccInject_c, RegEccInjectReset_c, "ECC_INJECT reads zero");
                regCheck(win(0, RegWinCtrl_c), x"00FF0037", "window 0 open");
                regCheck(win(0, RegWinBase_c), x"00000000", "window 0 base");
                regCheck(win(0, RegWinLast_c), x"FFFFFFFF", "window 0 last");
                regCheck(win(1, RegWinCtrl_c), x"00121223", "window 1 control");
                regCheck(win(1, RegWinBase_c), x"00001000", "window 1 base");
                regCheck(win(1, RegWinLast_c), x"00001FFF", "window 1 last");

                for n in 2 to WinMax_c - 1 loop

                    for r in 0 to 2 loop
                        regCheck(win(n, RegWinCtrl_c + 4 * r), x"00000000", "window " & to_string(n) & " reads zero");
                    end loop;

                end loop;

                regCheck(16#0FC#, x"00000000", "unused address reads zero");
                regCheck(16#3FC#, x"00000000", "unused address reads zero");
                check_value(MibOut.La0, x"42", error, "LA0 output");
                check_value(MibOut.La0En, '1', error, "LA0 enable output");
                check_value(MibOut.La1, x"43", error, "LA1 output");
                check_value(MibOut.La1En, '0', error, "LA1 enable output");
                check_value(MibOut.DefLaEn, '0', error, "default LA enable output");
                check_value(MibOut.Key, x"5A", error, "key output");
                check_value(MibOut.KeyEn, '1', error, "key enable output");
                check_value(MibOut.TickCycles, x"00C7", error, "tick output");
                check_value(MibOut.Timeout, x"03E8", error, "timeout output");
                check_value(MibOut.Win(0) = WinOpen_c, error, "window 0 output");
                check_value(MibOut.Win(1) = tbWin("10001", x"1200001000", x"1200001FFF"), error, "window 1 output");
                check_value(MibOut.Win(2) = WinDisabled_c, error, "window 2 output");
                check_value(MibOut.Irq, '0', error, "no interrupt");

            elsif run("test_config_registers") then
                -- TC-MB-02
                regWrite(RegTgtLa_c, x"FFFF3412");
                regCheck(RegTgtLa_c, x"00073412", "TGT_LA");
                regWrite(RegTgtKey_c, x"FFFFFE99");
                regCheck(RegTgtKey_c, x"00000099", "TGT_KEY");
                regWrite(RegIniTimeout_c, x"12345678");
                regCheck(RegIniTimeout_c, x"12345678", "INI_TIMEOUT");
                regWrite(RegIrqEn_c, x"FFFFFFFF");
                regCheck(RegIrqEn_c, x"000001FF", "IRQ_EN");
                regWrite(RegIrqEn_c, x"00000000");
                regWrite(RegEccSelect_c, x"FFFFFFFE");
                regCheck(RegEccSelect_c, x"00000002", "ECC_SELECT");
                wait for 50 ns;
                check_value(MibOut.La0, x"12", error, "LA0");
                check_value(MibOut.La1, x"34", error, "LA1");
                check_value(std_logic_vector'(MibOut.La0En & MibOut.La1En & MibOut.DefLaEn), "111", error, "LA enables");
                check_value(MibOut.Key, x"99", error, "key");
                check_value(MibOut.KeyEn, '0', error, "key not checked");
                check_value(MibOut.TickCycles, x"5678", error, "tick");
                check_value(MibOut.Timeout, x"1234", error, "timeout");
                regWrite(RegTgtLa_c, x"00000000");
                regCheck(RegTgtLa_c, x"00000000", "TGT_LA cleared");
                wait for 50 ns;
                check_value(std_logic_vector'(MibOut.La0En & MibOut.La1En & MibOut.DefLaEn), "000", error, "LA enables cleared");

                -- Windows: every field of the implemented windows
                for n in 0 to 3 loop
                    Data_v := x"FF" & std_logic_vector(to_unsigned(16#30# + n, 8)) & std_logic_vector(to_unsigned(16#20# + n, 8))
                              & "11" & std_logic_vector(to_unsigned(n + 1, 6));
                    regWrite(win(n, RegWinCtrl_c), Data_v);
                    regWrite(win(n, RegWinBase_c), std_logic_vector(to_unsigned(16#1000# * (n + 1), 32)));
                    regWrite(win(n, RegWinLast_c), std_logic_vector(to_unsigned(16#1000# * (n + 1) + 16#FFF#, 32)));
                end loop;

                for n in 0 to 3 loop
                    Data_v := x"00" & std_logic_vector(to_unsigned(16#30# + n, 8)) & std_logic_vector(to_unsigned(16#20# + n, 8))
                              & "00" & std_logic_vector(to_unsigned(n + 1, 6));
                    regCheck(win(n, RegWinCtrl_c), Data_v, "window " & to_string(n) & " control");
                    regCheck(win(n, RegWinBase_c), std_logic_vector(to_unsigned(16#1000# * (n + 1), 32)), "base");
                    regCheck(win(n, RegWinLast_c), std_logic_vector(to_unsigned(16#1000# * (n + 1) + 16#FFF#, 32)), "last");
                    check_value(std_logic_vector'(MibOut.Win(n).Single & MibOut.Win(n).Rmw & MibOut.Win(n).VerifiedOnly
                                                  & MibOut.Win(n).Write & MibOut.Win(n).Read & MibOut.Win(n).Enable),
                                Data_v(5 downto 0), error, "window " & to_string(n) & " permissions");
                    check_value(MibOut.Win(n).Base, Data_v(15 downto 8) & std_logic_vector(to_unsigned(16#1000# * (n + 1), 32)),
                                error, "window " & to_string(n) & " base output");
                    check_value(MibOut.Win(n).Last, Data_v(23 downto 16) & std_logic_vector(to_unsigned(16#1000# * (n + 1) + 16#FFF#, 32)),
                                error, "window " & to_string(n) & " last output");
                end loop;

                -- The fourth word of a window is unused
                regWrite(win(1, RegWinCtrl_c) + 16#C#, x"FFFFFFFF");
                regCheck(win(1, RegWinCtrl_c) + 16#C#, x"00000000", "unused word of a window reads zero");
                regCheck(win(1, RegWinCtrl_c), x"00312102", "window 1 unchanged");

                -- Windows beyond Windows_g ignore writes
                regWrite(win(5, RegWinCtrl_c), x"00000000");
                regWrite(win(5, RegWinBase_c), x"00001000");
                regCheck(win(5, RegWinCtrl_c), x"00000000", "window 5 reads zero");
                check_value(MibOut.Win(5) = WinOpen_c, error, "window 5 output unchanged");

                -- Read-only registers ignore writes
                regWrite(RegId_c, x"FFFFFFFF");
                regWrite(RegGenerics_c, x"FFFFFFFF");
                regWrite(RegBuffers_c, x"FFFFFFFF");
                regWrite(RegTgtLast_c, x"FFFFFFFF");
                regWrite(RegTgtLastAddr_c, x"FFFFFFFF");
                regWrite(RegIniStatus_c, x"FFFFFFFF");
                regWrite(RegIrqStatus_c, x"FFFFFFFF");
                regCheck(RegId_c, RegMapId_c, "ID unchanged");
                regCheck(RegGenerics_c, x"0808084B", "GENERICS unchanged");
                regCheck(RegBuffers_c, x"00400200", "BUFFERS unchanged");
                regCheck(RegTgtLast_c, x"00000000", "TGT_LAST unchanged");
                regCheck(RegTgtLastAddr_c, x"00000000", "TGT_LAST_ADDR unchanged");
                regCheck(RegIniStatus_c, x"00000000", "INI_STATUS unchanged");
                regCheck(RegIrqStatus_c, x"00000000", "IRQ_STATUS unchanged");

            elsif run("test_target_status") then
                -- TC-MB-03
                ind(x"7C", StatusOk_c, '1', x"21", x"1234", x"05A0000010");
                regCheck(RegTgtLast_c, x"01217C00", "last command: status, instruction, ILA, replied");
                regCheck(RegTgtLastTid_c, x"00001234", "last TID");
                regCheck(RegTgtLastAddr_c, x"A0000010", "last address");
                regCheck(RegTgtLastAddrExt_c, x"00000005", "last extended address");
                checkEvents("000000100", "TGT_CMD");
                ind(x"4C", StatusOk_c);
                ind(x"48", StatusOk_c, '0', x"33", x"BEEF", x"FF12345678");
                regCheck(RegTgtLast_c, x"00334800", "last command without reply");
                regCheck(RegTgtLastTid_c, x"0000BEEF", "last TID");
                regCheck(RegTgtLastAddr_c, x"12345678", "last address");
                regCheck(RegTgtLastAddrExt_c, x"000000FF", "last extended address");
                ind(x"5C", StatusOk_c);
                ind(x"6C", StatusOk_c);
                regCheck(RegTgtCntOk_c, x"00020002", "two writes and two reads");
                checkEvents("000000100", "TGT_CMD");

                -- Every status code of ECSS 5.6 counted in its own counter
                ind(x"7C", StatusGeneral_c);
                checkEvents("000000001", "TGT_ERROR");
                ind(x"7C", StatusUnused_c);
                ind(x"7C", StatusKey_c);
                ind(x"7C", StatusDataCrc_c);
                ind(x"7C", StatusEarlyEop_c);
                ind(x"7C", StatusTooMuch_c);
                ind(x"7C", StatusEep_c);
                ind(x"7C", StatusVerifyOverrun_c);
                ind(x"4C", StatusNotAuth_c);
                ind(x"5C", StatusRmwLength_c);
                ind(x"4C", StatusTla_c, '0');
                ind(x"4C", x"08");
                regCheck(RegTgtLast_c, x"01FE4C08", "last status");
                checkEvents("000000001", "TGT_ERROR");
                regCheck(RegTgtCntOk_c, x"00020002", "no further executed commands");
                regCheck(RegTgtCntErr1_c, x"00010001", "general error, unused command code");
                regCheck(RegTgtCntErr2_c, x"00010001", "key, Data CRC");
                regCheck(RegTgtCntErr3_c, x"00010001", "early EOP, too much data");
                regCheck(RegTgtCntErr4_c, x"00010001", "EEP, verify buffer overrun");
                regCheck(RegTgtCntErr5_c, x"00010001", "not authorised, RMW Data Length");

                -- Events of the target
                event(EvRepSent_c, 3);
                regCheck(RegTgtCntOk2_c, x"00030001", "RMW and replies");
                checkEvents("000000000", "replies set no flag");
                event(EvHdrCrc_c);
                checkEvents("000000010", "TGT_DISCARD by a Header CRC error");
                event(EvHdrShort_c, 2);
                checkEvents("000000010", "TGT_DISCARD by an incomplete header");
                event(EvReplyRx_c);
                checkEvents("000000010", "TGT_DISCARD by a reply");
                regCheck(RegTgtCntHdr_c, x"00020001", "header errors");
                regCheck(RegTgtCntErr6_c, x"00010001", "TLA, replies received");

            elsif run("test_initiator_status") then
                -- TC-MB-04
                MibIn.IniOpen <= x"05";
                wait for 50 ns;
                regCheck(RegIniStatus_c, x"00000005", "outstanding commands");
                event(EvCmdSent_c, 3);
                checkEvents("000000000", "commands sent set no flag");
                event(EvRepOk_c, 2);
                checkEvents("000001000", "INI_REPLY");
                event(EvHdrErr_c);
                checkEvents("000010000", "INI_ERROR by a header error");
                event(EvDataErr_c, 2);
                checkEvents("000010000", "INI_ERROR by a data error");
                event(EvUnexpected_c);
                checkEvents("000010000", "INI_ERROR by an unexpected reply");
                event(EvTidBusy_c);
                checkEvents("000010000", "INI_ERROR by a rejected request");
                event(EvTimeout_c, 3);
                checkEvents("000100000", "INI_TIMEOUT");
                event(EvCmdRx_c, 2);
                checkEvents("100000000", "PKT_DISCARD by a command without target");
                event(EvDiscard_c);
                checkEvents("100000000", "PKT_DISCARD by a packet without user port");
                event(EvUser_c, 4);
                checkEvents("000000000", "packets to the user port set no flag");
                regCheck(RegIniCnt1_c, x"00020003", "commands sent, replies confirmed");
                regCheck(RegIniCnt2_c, x"00020001", "header errors, data errors");
                regCheck(RegIniCnt3_c, x"00030001", "unexpected replies, timeouts");
                regCheck(RegIniCnt4_c, x"00020001", "rejected requests, commands without target");
                regCheck(RegPktCnt_c, x"00010004", "user packets, discarded packets");

            elsif run("test_flags_counters") then

                -- TC-MB-05: write one clears only the written flags
                for n in 0 to 8 loop
                    setEvent(n);
                end loop;

                regCheck(RegEvents_c, x"000001FF", "all flags set");
                regWrite(RegEvents_c, x"000000AA");
                regCheck(RegEvents_c, x"00000155", "written flags cleared");
                regWrite(RegEvents_c, x"00000155");
                regCheck(RegEvents_c, x"00000000", "all flags cleared");

                -- Any write clears both counters of the written register only
                regWrite(RegIniCnt1_c, x"00000000");
                regWrite(RegPktCnt_c, x"00000000");
                event(EvCmdSent_c, 2);
                event(EvRepOk_c, 1);
                event(EvUser_c, 3);
                regCheck(RegIniCnt1_c, x"00010002", "INI_CNT1");
                regWrite(RegIniCnt1_c, x"00000000");
                regCheck(RegIniCnt1_c, x"00000000", "INI_CNT1 cleared");
                regCheck(RegPktCnt_c, x"00000003", "PKT_CNT kept");
                regWrite(RegPktCnt_c, x"FFFFFFFF");
                regCheck(RegPktCnt_c, x"00000000", "PKT_CNT cleared");

                -- Saturation at 0xFFFF
                wait until rising_edge(Clk);
                MibIn.Ev(EvUser_c) <= '1';

                for i in 1 to 65540 loop
                    wait until rising_edge(Clk);
                end loop;

                MibIn.Ev(EvUser_c) <= '0';
                regCheck(RegPktCnt_c, x"0000FFFF", "saturated counter");
                event(EvUser_c);
                regCheck(RegPktCnt_c, x"0000FFFF", "saturated counter stays");

                -- An event in the cycle of a clear is kept
                regWrite(RegEvents_c, x"000001FF");
                MibIn.OnWrite <= '1';
                regWrite(RegIniCnt1_c, x"00000000");
                regCheck(RegIniCnt1_c, x"00010001", "events in the cycle of the counter clear counted");
                regWrite(RegEvents_c, x"00000008");
                regCheck(RegEvents_c, x"00000008", "event in the cycle of the flag clear kept");
                MibIn.OnWrite <= '0';
                wait for 50 ns;
                regWrite(RegEvents_c, x"00000008");
                regCheck(RegEvents_c, x"00000000", "flag cleared");

            elsif run("test_irq") then

                -- TC-MB-06
                for n in 0 to 8 loop
                    setEvent(n);
                end loop;

                wait for 50 ns;
                check_value(MibOut.Irq, '0', error, "no interrupt without enable");
                regCheck(RegIrqStatus_c, x"00000000", "IRQ_STATUS");
                regWrite(RegEvents_c, x"000001FF");

                for n in 0 to 8 loop
                    regWrite(RegIrqEn_c, std_logic_vector(to_unsigned(2 ** n, 32)));
                    setEvent((n + 1) mod 9);
                    check_value(MibOut.Irq, '0', error, "flag " & to_string((n + 1) mod 9) & " not enabled");
                    setEvent(n);
                    check_value(MibOut.Irq, '1', error, "interrupt by flag " & to_string(n));
                    regCheck(RegIrqStatus_c, x"00000001", "IRQ_STATUS");
                    regWrite(RegEvents_c, std_logic_vector(to_unsigned(2 ** n, 32)));
                    wait for 50 ns;
                    check_value(MibOut.Irq, '0', error, "interrupt cleared with flag " & to_string(n));
                    regWrite(RegEvents_c, x"000001FF");
                end loop;

            elsif run("test_ecc") then
                -- TC-MB-07: counters, flags and events per channel
                eccEvent(0, 0);
                eccEvent(0, 0);
                eccEvent(1, 0);
                eccEvent(1, 1);
                eccEvent(2, 0);
                eccEvent(2, 0);
                eccEvent(2, 0);
                eccEvent(2, 1);
                eccEvent(2, 1);
                regCheck(RegEccStatus_c, x"00000006", "DED flags of channels 1 and 2");
                regCheck(RegEvents_c, x"000000C0", "ECC_SEC and ECC_DED");
                regCheck(RegEccCount_c, x"00000002", "channel 0");
                regWrite(RegEccSelect_c, x"00000001");
                regCheck(RegEccCount_c, x"00010001", "channel 1");
                regWrite(RegEccSelect_c, x"00000002");
                regCheck(RegEccCount_c, x"00020003", "channel 2");
                regWrite(RegEccSelect_c, x"00000003");
                regCheck(RegEccCount_c, x"00000000", "channel 3 does not exist");

                -- Clear of the selected channel, global clear
                regWrite(RegEccSelect_c, x"00000002");
                regWrite(RegEccCount_c, x"00000000");
                regCheck(RegEccCount_c, x"00000000", "channel 2 cleared");
                regCheck(RegEccStatus_c, x"00000002", "DED flag of channel 2 cleared");
                regWrite(RegEccSelect_c, x"00000001");
                regCheck(RegEccCount_c, x"00010001", "channel 1 kept");
                regWrite(RegEccStatus_c, x"00000000");
                regCheck(RegEccStatus_c, x"00000000", "global clear of the flags");
                regCheck(RegEccCount_c, x"00000000", "global clear of the counters");
                regWrite(RegEccSelect_c, x"00000000");
                regCheck(RegEccCount_c, x"00000000", "channel 0 cleared");

                -- Injection commands
                regWrite(RegEccInject_c, x"00000100");
                wait for 50 ns;
                check_value(MibOut.CntInj(0), 1, error, "single error into channel 0");
                check_value(MibOut.LastDouble, '0', error, "single error");
                regWrite(RegEccInject_c, x"00000201");
                wait for 50 ns;
                check_value(MibOut.CntInj(1), 1, error, "double error into channel 1");
                check_value(MibOut.LastDouble, '1', error, "double error");
                regWrite(RegEccInject_c, x"00000102");
                wait for 50 ns;
                check_value(MibOut.CntInj(2), 1, error, "single error into channel 2");
                check_value(MibOut.LastDouble, '0', error, "single error");
                regWrite(RegEccInject_c, x"00000002");
                regWrite(RegEccInject_c, x"00000103");
                wait for 50 ns;
                check_value(MibOut.CntInj(0) + MibOut.CntInj(1) + MibOut.CntInj(2), 3, error,
                            "no injection without SINGLE or DOUBLE and into channel 3");
                regCheck(RegEccInject_c, x"00000000", "ECC_INJECT reads zero");
            end if;

        end loop;

        ormTestEnd(runner);
    end process;

    i_th : entity work.orm_mib_th
        port map (
            Clk    => Clk,
            Rst    => Rst,
            MibIn  => MibIn,
            MibOut => MibOut
        );

end architecture;
