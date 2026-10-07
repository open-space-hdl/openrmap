---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Core testbench: two cores connected by a packet network model. The Initiator of each core
-- accesses the memory of the other core; commands of ECSS Annex A.4, packets of other protocols and
-- network faults are injected; the register files are read through AXI4-Lite.
--
-- Documentation: hdl/omap_core/docs/verification_plan.md

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

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.omap_pkg.all;
    use work.omap_regs_pkg.all;
    use work.omap_tb_pkg.all;
    use work.omap_tb_rmap_pkg.all;
    use work.omap_tb_mem_pkg.all;
    use work.omap_tb_memvar_pkg.all;
    use work.omap_initiator_tb_pkg.all;
    use work.omap_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_core_tb is
    generic (
        runner_cfg     : string;
        TargetA_g      : boolean := true;
        InitiatorB_g   : boolean := true;
        PassB_g        : boolean := true;
        Transactions_g : natural := 1
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_core_tb is

    constant A_c : natural := 0;
    constant B_c : natural := 1;

    signal Clk      : std_logic;
    signal Rst      : std_logic      := '1';
    signal Req      : IniReqArray_t  := (others => IniReqInit_c);
    signal ReqReady : std_logic_vector(0 to 1);
    signal NetCtrl  : NetCtrlArray_t := (others => NetCtrlInit_c);
    signal Obs      : CoreObsArray_t;

begin

    test_runner_watchdog(runner, 20 ms);

    p_main : process is
        variable Cmd_v  : TbCmd_t;
        variable Data_v : t_slv_array(0 to 15)(7 downto 0);
        variable Conf_v : natural;

        procedure regWrite (
            c    : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, c, to_unsigned(addr, 10), data, "write 0x" & to_hstring(to_unsigned(addr, 12)));
            await_completion(AXILITE_VVCT, c, 100 us);
        end procedure;

        procedure regCheck (
            c    : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, c, to_unsigned(addr, 10), data, msg);
            await_completion(AXILITE_VVCT, c, 100 us);
        end procedure;

        -- Request of the Initiator of core c to the Target of the other core (or to the logical address tla)
        procedure request (
            c     : natural;
            instr : std_logic_vector(7 downto 0);
            addr  : natural;
            len   : natural;
            tid   : natural;
            data  : t_slv_array;
            key   : std_logic_vector(7 downto 0) := x"00";
            tla   : std_logic_vector(7 downto 0) := x"00") is
            variable R_v : IniReq_t := IniReqInit_c;
        begin
            R_v.Valid := '1';
            R_v.Code  := instr(5 downto 2);
            if tla = x"00" then
                R_v.Tla := CoreLa_c(1 - c);
            else
                R_v.Tla := tla;
            end if;
            R_v.Key  := key;
            R_v.Ila  := CoreLa_c(c);
            R_v.Tid  := std_logic_vector(to_unsigned(tid, 16));
            R_v.Addr := std_logic_vector(to_unsigned(addr, 40));
            R_v.Len  := std_logic_vector(to_unsigned(len, 24));
            if data'length > 0 then
                axistream_transmit(AXISTREAM_VVCT, VvcCoReqData_c + c, data, "request data");
            end if;
            wait until rising_edge(Clk);
            Req(c) <= R_v;

            loop
                wait until rising_edge(Clk);
                exit when ReqReady(c) = '1';
            end loop;

            Req(c).Valid <= '0';
        end procedure;

        -- Waits for n confirmations of core c in total
        procedure awaitConf (
            c   : natural;
            n   : natural;
            msg : string) is
            variable Start_v : time;
        begin
            Start_v := now;

            while Obs(c).ConfCnt < n and now < Start_v + 2 ms loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Obs(c).ConfCnt, n, error, msg & ": confirmations");
        end procedure;

        -- Confirmation number idx of core c; the status is not checked for a timeout or a rejected request
        procedure checkConf (
            c      : natural;
            idx    : natural;
            tid    : natural;
            status : std_logic_vector(7 downto 0);
            err    : std_logic_vector(1 downto 0);
            msg    : string) is
        begin
            check_value(Obs(c).Conf(idx mod 64).Tid, std_logic_vector(to_unsigned(tid, 16)), error, msg & ": TID");
            check_value(Obs(c).Conf(idx mod 64).Error, err, error, msg & ": local error");
            if err = "00" or err = "01" then
                check_value(Obs(c).Conf(idx mod 64).Status, status, error, msg & ": status");
            end if;
        end procedure;

        -- Request of core c and its confirmation
        procedure transfer (
            c      : natural;
            instr  : std_logic_vector(7 downto 0);
            addr   : natural;
            len    : natural;
            tid    : natural;
            data   : t_slv_array;
            status : std_logic_vector(7 downto 0);
            err    : std_logic_vector(1 downto 0);
            msg    : string;
            key    : std_logic_vector(7 downto 0) := x"00";
            tla    : std_logic_vector(7 downto 0) := x"00") is
            variable Cnt_v : natural;
        begin
            Cnt_v := Obs(c).ConfCnt;
            request(c, instr, addr, len, tid, data, key, tla);
            awaitConf(c, Cnt_v + 1, msg);
            checkConf(c, Cnt_v, tid, status, err, msg);
        end procedure;

        procedure checkMem (
            m    : natural;
            addr : natural;
            data : t_slv_array;
            msg  : string) is
            variable Ok_v : boolean := true;
        begin

            for i in 0 to data'length - 1 loop
                if Mem_v.read8(m, addr + i) /= data(data'low + i) then
                    Ok_v := false;
                    alert(ERROR, msg & ": memory byte " & to_string(i) & " at 0x" & to_hstring(to_unsigned(addr + i, 16))
                          & " is 0x" & to_hstring(Mem_v.read8(m, addr + i)) & ", expected 0x"
                          & to_hstring(data(data'low + i)));
                    exit;
                end if;
            end loop;

            check_value(Ok_v, error, msg);
        end procedure;

        -- Packet through the user port of core c
        procedure userSend (
            c     : natural;
            bytes : t_slv_array;
            eep   : boolean := false) is
        begin
            axistream_transmit(AXISTREAM_VVCT, VvcCoUsrTx_c + c, omapPacket(bytes, eep), "user packet");
        end procedure;

        procedure userExpect (
            c     : natural;
            bytes : t_slv_array;
            msg   : string;
            eep   : boolean := false) is
        begin
            axistream_expect(AXISTREAM_VVCT, VvcCoUsrRx_c + c, omapPacket(bytes, eep), msg);
        end procedure;

        procedure awaitStreams is
        begin

            for i in 0 to 9 loop
                await_completion(AXISTREAM_VVCT, i, 2 ms, "VVC " & to_string(i));
            end loop;

        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);

        for i in 0 to 9 loop
            disable_log_msg(AXISTREAM_VVCT, i, ALL_MESSAGES);
        end loop;

        for c in 0 to 1 loop
            disable_log_msg(AXILITE_VVCT, c, ALL_MESSAGES);
        end loop;

        while test_suite loop

            NetCtrl <= (others => NetCtrlInit_c);
            Rst     <= '1';
            wait for 100 ns;
            wait until rising_edge(Clk);
            Rst     <= '0';
            wait for 100 ns;

            if run("test_annex_patterns") then
                -- TC-CO-01: commands of ECSS Annex A.4 from the network, replies to the network
                NetCtrl(B_c).Capture <= '1';
                Cmd_v                := tbCmd(x"6C", 0, 16, 0);
                Cmd_v.Addr           := x"A0000000";
                Data_v               := (x"01",
                                         x"23",
                                         x"45",
                                         x"67",
                                         x"89",
                                         x"AB",
                                         x"CD",
                                         x"EF",
                                         x"10",
                                         x"11",
                                         x"12",
                                         x"13",
                                         x"14",
                                         x"15",
                                         x"16",
                                         x"17");
                userSend(A_c, tbCommand(Cmd_v, Data_v));
                axistream_expect(AXISTREAM_VVCT, VvcCoCap_c + B_c, omapPacket(tbWriteReply(Cmd_v, x"00")), "write reply");
                Cmd_v                := tbCmd(x"4C", 0, 16, 1);
                Cmd_v.Addr           := x"A0000000";
                userSend(A_c, tbCommand(Cmd_v, tbBytes(0)));
                axistream_expect(AXISTREAM_VVCT, VvcCoCap_c + B_c, omapPacket(tbReadReply(Cmd_v, x"00", 16, Data_v)), "read reply");
                Cmd_v                := tbCmd(x"6E", 0, 16, 2);
                Cmd_v.Addr           := x"A0000010";
                Cmd_v.ReplyAddr      := x"00000000" & x"00EEDDCCBBAA9900";
                userSend(A_c, tbCommand(Cmd_v, tbBytes(16, 16#A0#)));
                axistream_expect(AXISTREAM_VVCT, VvcCoCap_c + B_c, omapPacket(tbWriteReply(Cmd_v, x"00")),
                                 "write reply with Reply SpaceWire Address");
                Cmd_v                := tbCmd(x"4D", 0, 16, 3);
                Cmd_v.Addr           := x"A0000010";
                Cmd_v.ReplyAddr      := x"0000000000000000" & x"CCBBAA99";
                userSend(A_c, tbCommand(Cmd_v, tbBytes(0)));
                axistream_expect(AXISTREAM_VVCT, VvcCoCap_c + B_c, omapPacket(tbReadReply(Cmd_v, x"00", 16, tbBytes(16, 16#A0#))),
                                 "read reply with Reply SpaceWire Address");
                awaitStreams;
                checkMem(B_c, 0, Data_v, "memory written by the first command");
                checkMem(B_c, 16#10#, tbBytes(16, 16#A0#), "memory written by the third command");
                check_value(Obs(B_c).IndCnt, 4, error, "four indications of the Target");
                regCheck(B_c, RegTgtCntOk_c, x"00020002", "two writes and two reads");
                regCheck(B_c, RegTgtCntOk2_c, x"00040000", "four replies");
                regCheck(B_c, RegPktCnt_c, x"00000000", "no packet to the user port");
                regCheck(A_c, RegPktCnt_c, x"00000000", "no packet received by core A");

            elsif run("test_write_read") then
                -- TC-CO-02: Initiator of A to Target of B and the reverse at the same time
                Conf_v := 0;
                request(A_c, x"7C", 16#100#, 16, 1, tbBytes(16, 1));
                request(B_c, x"6C", 16#400#, 64, 11, tbBytes(64, 11));
                request(A_c, x"6C", 16#200#, 100, 2, tbBytes(100, 2));
                request(B_c, x"4C", 16#400#, 64, 12, tbBytes(0));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + B_c, tbBytes(64, 11), "read data of B");
                request(A_c, x"4C", 16#200#, 100, 3, tbBytes(0));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(100, 2), "read data of A");
                -- Read-modify-write: data 0xF0 0x0F, mask 0xFF 0xF0 on 0x01 0x02 gives 0xF0 0x02
                request(A_c, x"5C", 16#100#, 4, 4, tbCat(tbCat(tbOne(x"F0"), tbOne(x"0F")), tbCat(tbOne(x"FF"), tbOne(x"F0"))));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbCat(tbOne(x"01"), tbOne(x"02")), "old data of the read-modify-write");
                -- Single-address write of one word (8 bytes at B) and write without reply
                request(A_c, x"68", 16#300#, 8, 5, tbBytes(8, 16#50#));
                request(A_c, x"64", 16#500#, 10, 6, tbBytes(10, 16#60#));
                request(A_c, x"4C", 16#500#, 10, 7, tbBytes(0));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(10, 16#60#), "data written without reply");
                awaitConf(A_c, 6, "A");
                awaitConf(B_c, 2, "B");
                checkConf(A_c, 0, 1, x"00", "00", "verified write");
                checkConf(A_c, 1, 2, x"00", "00", "write");
                checkConf(A_c, 2, 3, x"00", "00", "read");
                checkConf(A_c, 3, 4, x"00", "00", "read-modify-write");
                checkConf(A_c, 4, 5, x"00", "00", "single-address write");
                checkConf(A_c, 5, 7, x"00", "00", "read after a write without reply");
                checkConf(B_c, 0, 11, x"00", "00", "write of B");
                checkConf(B_c, 1, 12, x"00", "00", "read of B");
                check_value(Obs(A_c).Conf(3).Len, x"000002", error, "Data Length of the read-modify-write reply");
                awaitStreams;
                checkMem(B_c, 16#100#, tbCat(tbOne(x"F0"), tbOne(x"02")), "read-modify-write");
                checkMem(B_c, 16#102#, tbBytes(14, 3), "rest of the verified write");
                checkMem(B_c, 16#300#, tbBytes(8, 16#50#), "single-address write");
                checkMem(A_c, 16#400#, tbBytes(64, 11), "write of B");
                regCheck(B_c, RegTgtCntOk_c, x"00020004", "B: four writes, two reads");
                regCheck(B_c, RegTgtCntOk2_c, x"00060001", "B: one read-modify-write, six replies");
                regCheck(A_c, RegIniCnt1_c, x"00060007", "A: seven commands, six replies");
                regCheck(A_c, RegTgtCntOk_c, x"00010001", "A: one write, one read");
                regCheck(B_c, RegIniCnt1_c, x"00020002", "B: two commands, two replies");
                regCheck(A_c, RegIniStatus_c, x"00000000", "A: no outstanding command");

            elsif run("test_errors") then
                -- TC-CO-03: faults in the network and rejected commands
                Mem_v.fill(B_c, 16#100#, 64, 16#80#);
                Mem_v.fill(B_c, 16#FFC#, 4, 0);
                -- Header CRC error in the command: discarded by B, timeout at A
                NetCtrl(A_c) <= (Capture => '0', Fault => FaultFlip_c, Idx => 4);
                transfer(A_c, x"7C", 16#100#, 16, 1, tbBytes(16), x"00", "10", "command with a Header CRC error");
                NetCtrl(A_c) <= NetCtrlInit_c;
                -- Data CRC error in a verified write: status 4, memory unchanged
                NetCtrl(A_c) <= (Capture => '0', Fault => FaultFlip_c, Idx => 16);
                transfer(A_c, x"7C", 16#100#, 16, 2, tbBytes(16), StatusDataCrc_c, "00", "verified write with a Data CRC error");
                NetCtrl(A_c) <= NetCtrlInit_c;
                -- EEP in the data of a verified write: status 7
                NetCtrl(A_c) <= (Capture => '0', Fault => FaultTruncate_c, Idx => 18);
                transfer(A_c, x"7C", 16#100#, 16, 3, tbBytes(16), StatusEep_c, "00", "verified write ended by an EEP");
                NetCtrl(A_c) <= NetCtrlInit_c;
                checkMem(B_c, 16#100#, tbBytes(64, 16#80#), "memory unchanged");
                -- Data CRC error in a read reply: data error at A
                NetCtrl(B_c) <= (Capture => '0', Fault => FaultFlip_c, Idx => 13);
                Data_v       := tbBytes(16, 16#80#);
                Data_v(1)    := Data_v(1) xor x"10";
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, Data_v, "corrupted read data");
                transfer(A_c, x"4C", 16#100#, 16, 4, tbBytes(0), x"00", "01", "read reply with a Data CRC error");
                NetCtrl(B_c) <= NetCtrlInit_c;
                -- Header CRC error in a reply: discarded, timeout
                NetCtrl(B_c) <= (Capture => '0', Fault => FaultFlip_c, Idx => 3);
                transfer(A_c, x"6C", 16#200#, 4, 5, tbBytes(4), x"00", "10", "reply with a Header CRC error");
                NetCtrl(B_c) <= NetCtrlInit_c;
                -- Reply lost: timeout
                NetCtrl(B_c) <= (Capture => '0', Fault => FaultDrop_c, Idx => 0);
                transfer(A_c, x"6C", 16#200#, 4, 6, tbBytes(4), x"00", "10", "reply lost");
                NetCtrl(B_c) <= NetCtrlInit_c;
                -- Rejected by the Target: key, Target Logical Address, address window
                transfer(A_c, x"6C", 16#200#, 4, 7, tbBytes(4), StatusKey_c, "00", "wrong key", key => x"99");
                transfer(A_c, x"4C", 16#200#, 4, 8, tbBytes(0), StatusTla_c, "00", "wrong Target Logical Address",
                         tla => x"55");
                regWrite(B_c, RegWinCtrl_c, x"00000007");
                regWrite(B_c, RegWinLast_c, x"00000FFF");
                transfer(A_c, x"4C", 16#2000#, 4, 9, tbBytes(0), StatusNotAuth_c, "00", "read outside the windows");
                request(A_c, x"4C", 16#FFC#, 4, 10, tbBytes(0));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(4), "read inside the window");
                awaitConf(A_c, 10, "read inside the window");
                checkConf(A_c, 9, 10, x"00", "00", "read inside the window");
                awaitStreams;
                regCheck(B_c, RegTgtCntHdr_c, x"00000001", "B: one Header CRC error");
                regCheck(B_c, RegTgtCntErr2_c, x"00010001", "B: key, Data CRC");
                regCheck(B_c, RegTgtCntErr4_c, x"00000001", "B: EEP");
                regCheck(B_c, RegTgtCntErr5_c, x"00000001", "B: not authorised");
                regCheck(B_c, RegTgtCntErr6_c, x"00000001", "B: Target Logical Address");
                regCheck(A_c, RegIniCnt2_c, x"00010001", "A: header error, data error");
                regCheck(A_c, RegIniCnt3_c, x"00030000", "A: three timeouts");
                regCheck(A_c, RegEvents_c, x"00000038", "A: INI_TIMEOUT, INI_ERROR, INI_REPLY");

            elsif run("test_passthrough") then
                -- TC-CO-04: packets of other protocols in both directions, interleaved with RMAP packets
                userExpect(B_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"02")), tbBytes(18, 16#40#)), "PID 2");
                userExpect(B_c, tbBytes(0), "empty packet");
                userExpect(B_c, tbOne(x"30"), "one character");
                userExpect(B_c, tbCat(tbOne(x"30"), tbOne(x"05")), "two characters");
                userExpect(B_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"00")), tbBytes(2, 1)), "extended protocol identifier with EEP", true);
                userExpect(B_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"F0")), tbBytes(300, 7)), "300 characters");
                userExpect(A_c, tbCat(tbCat(tbOne(x"20"), tbOne(x"03")), tbBytes(50, 9)), "PID 3");
                userExpect(A_c, tbOne(x"20"), "one character");
                request(A_c, x"6C", 16#1000#, 200, 1, tbBytes(200, 1));
                request(B_c, x"6C", 16#1000#, 100, 2, tbBytes(100, 2));
                userSend(A_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"02")), tbBytes(18, 16#40#)));
                userSend(A_c, tbBytes(0));
                userSend(B_c, tbCat(tbCat(tbOne(x"20"), tbOne(x"03")), tbBytes(50, 9)));
                userSend(A_c, tbOne(x"30"));
                request(A_c, x"4C", 16#1000#, 200, 3, tbBytes(0));
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(200, 1), "read data of A");
                userSend(A_c, tbCat(tbOne(x"30"), tbOne(x"05")));
                userSend(A_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"00")), tbBytes(2, 1)), true);
                userSend(B_c, tbOne(x"20"));
                userSend(A_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"F0")), tbBytes(300, 7)));
                awaitConf(A_c, 2, "A");
                awaitConf(B_c, 1, "B");
                checkConf(A_c, 0, 1, x"00", "00", "write of A");
                checkConf(A_c, 1, 3, x"00", "00", "read of A");
                checkConf(B_c, 0, 2, x"00", "00", "write of B");
                awaitStreams;
                checkMem(B_c, 16#1000#, tbBytes(200, 1), "write of A");
                checkMem(A_c, 16#1000#, tbBytes(100, 2), "write of B");
                regCheck(B_c, RegPktCnt_c, x"00000006", "B: six packets to the user port");
                regCheck(A_c, RegPktCnt_c, x"00000002", "A: two packets to the user port");

            elsif run("test_limited_nodes") then
                -- TC-CO-05: core A Initiator only, core B Target only
                regCheck(A_c, RegGenerics_c, x"08040106", "A: Initiator only");
                regCheck(B_c, RegGenerics_c, x"00080045", "B: Target only");
                transfer(A_c, x"6C", 16#100#, 32, 1, tbBytes(32, 5), x"00", "00", "write");
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(32, 5), "read data");
                transfer(A_c, x"4C", 16#100#, 32, 2, tbBytes(0), x"00", "00", "read");
                -- Reply received by the Target-only node: discarded (ECSS 5.7.1.3)
                Cmd_v     := tbCmd(x"6C", 0, 0, 77);
                Cmd_v.Ila := CoreLa_c(B_c);
                userSend(A_c, tbWriteReply(Cmd_v, x"00"));
                -- Command received by the Initiator-only node: discarded (ECSS 5.7.1.2)
                Cmd_v     := tbCmd(x"6C", 0, 4, 78);
                Cmd_v.Tla := CoreLa_c(A_c);
                userSend(B_c, tbCommand(Cmd_v, tbBytes(4)));
                -- RMAP packets that end before the instruction
                userSend(A_c, tbCat(tbOne(CoreLa_c(B_c)), tbOne(x"01")));
                userSend(B_c, tbCat(tbOne(CoreLa_c(A_c)), tbOne(x"01")));
                awaitStreams;
                wait for 2 us;
                regCheck(B_c, RegTgtCntErr6_c, x"00010000", "B: reply received");
                regCheck(B_c, RegTgtCntOk2_c, x"00020000", "B: no reply to the reply");
                regCheck(B_c, RegTgtCntHdr_c, x"00010000", "B: incomplete header");
                regCheck(A_c, RegIniCnt4_c, x"00010000", "A: command received");
                regCheck(A_c, RegIniCnt2_c, x"00000001", "A: incomplete header");
                regCheck(A_c, RegIniCnt3_c, x"00000000", "A: no unexpected reply");
                regCheck(A_c, RegEvents_c, x"00000118", "A: PKT_DISCARD, INI_ERROR, INI_REPLY");
                check_value(Obs(A_c).ConfCnt, 2, error, "A: no further confirmation");

            elsif run("test_no_passthrough") then
                -- TC-CO-06: core B without user port
                regCheck(B_c, RegGenerics_c, x"08080143", "B: without user port");
                regCheck(A_c, RegGenerics_c, x"08040147", "A: with user port");
                userSend(A_c, tbCat(tbCat(tbOne(x"30"), tbOne(x"02")), tbBytes(10)));
                userSend(A_c, tbOne(x"30"));
                userSend(A_c, tbCat(tbOne(x"30"), tbOne(x"05")));
                transfer(A_c, x"7C", 16#100#, 16, 1, tbBytes(16, 3), x"00", "00", "write");
                awaitStreams;
                checkMem(B_c, 16#100#, tbBytes(16, 3), "write");
                regCheck(B_c, RegPktCnt_c, x"00030000", "B: three packets discarded");
                regCheck(B_c, RegEvents_c, x"00000104", "B: PKT_DISCARD, TGT_CMD");

            elsif run("test_mib") then
                -- TC-CO-07: configuration of the Target through the register file, EDAC, interrupt
                regWrite(B_c, RegEccInject_c, x"00000100");
                transfer(A_c, x"7C", 16#600#, 16, 1, tbBytes(16, 9), x"00", "00", "verified write with a single error");
                checkMem(B_c, 16#600#, tbBytes(16, 9), "corrected data written");
                regCheck(B_c, RegEccCount_c, x"00000001", "B: one single error in the write buffer");
                regCheck(B_c, RegEvents_c, x"00000044", "B: ECC_SEC, TGT_CMD");
                regCheck(B_c, RegTgtLast_c, x"01207C00", "B: last command");
                check_value(Obs(B_c).Irq, '0', error, "no interrupt");
                regWrite(B_c, RegIrqEn_c, x"00000040");
                wait for 50 ns;
                check_value(Obs(B_c).Irq, '1', error, "interrupt by ECC_SEC");
                regWrite(B_c, RegEvents_c, x"000001FF");
                wait for 50 ns;
                check_value(Obs(B_c).Irq, '0', error, "interrupt cleared");
                -- Logical address and key
                regWrite(B_c, RegTgtLa_c, x"00010031");
                regWrite(B_c, RegTgtKey_c, x"0000015A");
                transfer(A_c, x"6C", 16#600#, 4, 2, tbBytes(4), StatusTla_c, "00", "old logical address");
                transfer(A_c, x"6C", 16#600#, 4, 3, tbBytes(4), StatusKey_c, "00", "old key", tla => x"31");
                transfer(A_c, x"6C", 16#600#, 4, 4, tbBytes(4, 16#C0#), x"00", "00", "new logical address and key",
                         key => x"5A", tla => x"31");
                checkMem(B_c, 16#600#, tbBytes(4, 16#C0#), "write with the new configuration");
                -- Read-only window
                regWrite(B_c, RegWinCtrl_c, x"00000003");
                transfer(A_c, x"6C", 16#600#, 4, 5, tbBytes(4), StatusNotAuth_c, "00", "write to a read-only window",
                         key => x"5A", tla => x"31");
                axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(4, 16#C0#), "read data");
                transfer(A_c, x"4C", 16#600#, 4, 6, tbBytes(0), x"00", "00", "read of a read-only window",
                         key => x"5A", tla => x"31");
                awaitStreams;

            elsif run("test_stress") then
                -- TC-CO-08: both Initiators, user packets in both directions, memory with backpressure
                regWrite(A_c, RegIniTimeout_c, x"00000009");
                regWrite(B_c, RegIniTimeout_c, x"00000009");
                Mem_v.setStall(A_c, 30);
                Mem_v.setStall(B_c, 30);

                for i in 0 to 7 loop
                    userExpect(B_c, tbCat(tbOne(x"30"), tbBytes(10 * i + 1, 16#40# + i)), "user packet to B");
                    userExpect(A_c, tbCat(tbOne(x"20"), tbBytes(7 * i + 2, 16#60# + i)), "user packet to A");
                    userSend(A_c, tbCat(tbOne(x"30"), tbBytes(10 * i + 1, 16#40# + i)));
                    userSend(B_c, tbCat(tbOne(x"20"), tbBytes(7 * i + 2, 16#60# + i)));
                end loop;

                for i in 0 to 15 loop
                    request(A_c, x"6C", 16#2000# + 64 * i, 3 * i + 1, 100 + i, tbBytes(3 * i + 1, i));
                    request(B_c, x"7C", 16#3000# + 64 * i, 2 * i + 1, 200 + i, tbBytes(2 * i + 1, 50 + i));
                end loop;

                for i in 0 to 15 loop
                    axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(3 * i + 1, i), "read data of A");
                    axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + B_c, tbBytes(2 * i + 1, 50 + i), "read data of B");
                    request(A_c, x"4C", 16#2000# + 64 * i, 3 * i + 1, 300 + i, tbBytes(0));
                    request(B_c, x"4C", 16#3000# + 64 * i, 2 * i + 1, 400 + i, tbBytes(0));
                end loop;

                awaitConf(A_c, 32, "A");
                awaitConf(B_c, 32, "B");

                for i in 0 to 31 loop
                    check_value(Obs(A_c).Conf(i).Status & "000000" & Obs(A_c).Conf(i).Error, x"0000", error,
                                "A: confirmation " & to_string(i));
                    check_value(Obs(B_c).Conf(i).Status & "000000" & Obs(B_c).Conf(i).Error, x"0000", error,
                                "B: confirmation " & to_string(i));
                end loop;

                awaitStreams;

                for i in 0 to 15 loop
                    checkMem(B_c, 16#2000# + 64 * i, tbBytes(3 * i + 1, i), "write of A " & to_string(i));
                    checkMem(A_c, 16#3000# + 64 * i, tbBytes(2 * i + 1, 50 + i), "write of B " & to_string(i));
                end loop;

                regCheck(A_c, RegIniCnt1_c, x"00200020", "A: 32 commands and replies");
                regCheck(B_c, RegIniCnt1_c, x"00200020", "B: 32 commands and replies");
                regCheck(A_c, RegPktCnt_c, x"00000008", "A: eight user packets");
                regCheck(B_c, RegPktCnt_c, x"00000008", "B: eight user packets");

            elsif run("test_pipelined") then
                -- TC-CO-09: eight outstanding commands of the Initiator of A, memory with backpressure
                regWrite(A_c, RegIniTimeout_c, x"00000009");
                Mem_v.setStall(B_c, 30);

                for i in 0 to 23 loop
                    request(A_c, x"6C", 16#4000# + 64 * i, 2 * i + 3, 500 + i, tbBytes(2 * i + 3, 3 * i));
                end loop;

                for i in 0 to 23 loop
                    axistream_expect(AXISTREAM_VVCT, VvcCoRepData_c + A_c, tbBytes(2 * i + 3, 3 * i), "read data");
                    request(A_c, x"4C", 16#4000# + 64 * i, 2 * i + 3, 600 + i, tbBytes(0));
                end loop;

                awaitConf(A_c, 48, "A");

                for i in 0 to 47 loop
                    check_value(Obs(A_c).Conf(i).Status & "000000" & Obs(A_c).Conf(i).Error, x"0000", error,
                                "confirmation " & to_string(i));
                end loop;

                awaitStreams;

                for i in 0 to 23 loop
                    checkMem(B_c, 16#4000# + 64 * i, tbBytes(2 * i + 3, 3 * i), "write " & to_string(i));
                end loop;

                regCheck(A_c, RegIniCnt1_c, x"00300030", "A: 48 commands and replies");
            end if;

        end loop;

        omapTestEnd(runner);
    end process;

    i_th : entity work.omap_core_th
        generic map (
            TargetA_g      => TargetA_g,
            InitiatorA_g   => true,
            PassA_g        => true,
            TargetB_g      => true,
            InitiatorB_g   => InitiatorB_g,
            PassB_g        => PassB_g,
            Transactions_g => Transactions_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Req          => Req,
            ReqReady     => ReqReady,
            NetCtrl      => NetCtrl,
            Obs          => Obs
        );

end architecture;
