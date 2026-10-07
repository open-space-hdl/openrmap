---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the RMAP Initiator: every command is compared byte by byte with the command built by
-- the RMAP model from the same fields; replies built by the model (also corrupted ones) are injected
-- and the confirmations and the reply data are checked.
--
-- Documentation: hdl/omap_initiator/docs/verification_plan.md

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

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.omap_pkg.all;
    use work.omap_tb_pkg.all;
    use work.omap_tb_rmap_pkg.all;
    use work.omap_initiator_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_initiator_tb is
    generic (
        runner_cfg     : string;
        Transactions_g : natural := 4
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_initiator_tb is

    signal Clk      : std_logic;
    signal Rst      : std_logic := '1';
    signal Req      : IniReq_t  := IniReqInit_c;
    signal Cfg      : IniCfg_t  := IniCfgInit_c;
    signal Obs      : IniObs_t;
    signal ReqReady : std_logic;

begin

    test_runner_watchdog(runner, 20 ms);

    p_main : process is
        variable Cmd_v  : TbCmd_t;
        variable Cmd2_v : TbCmd_t;
        variable Cnt_v  : natural;
        variable T_v    : time;

        -- Command with the Reply Address bytes ra (padded to whole words as the Initiator does it)
        impure function withRa (
            cmd : TbCmd_t;
            ra  : t_slv_array) return TbCmd_t is
            variable C_v   : TbCmd_t := cmd;
            variable Ral_v : natural;
        begin
            Ral_v         := (ra'length + 3) / 4;
            C_v.Instr     := cmd.Instr(7 downto 2) & std_logic_vector(to_unsigned(Ral_v, 2));
            C_v.ReplyAddr := (others => '0');

            for i in 0 to ra'length - 1 loop
                C_v.ReplyAddr(8 * (4 * Ral_v - ra'length + i) + 7 downto 8 * (4 * Ral_v - ra'length + i)) := ra(ra'low + i);
            end loop;

            return C_v;
        end function;

        -- Request built from the fields of cmd, its data and the Reply Address bytes ra; the command sent is
        -- expected as the model builds it
        function toReq (
            cmd : TbCmd_t;
            ra  : t_slv_array) return IniReq_t is
            variable R_v : IniReq_t := IniReqInit_c;
        begin
            R_v.Valid      := '1';
            R_v.Code       := cmd.Instr(5 downto 2);
            R_v.TgtAddr    := cmd.Path(63 downto 0);
            R_v.TgtAddrLen := cmd.PathLen;
            R_v.Tla        := cmd.Tla;
            R_v.Key        := cmd.Key;
            R_v.ReplyAddr  := (others => '0');

            for i in 0 to ra'length - 1 loop
                R_v.ReplyAddr(8 * i + 7 downto 8 * i) := ra(ra'low + i);
            end loop;

            R_v.ReplyAddrLen := ra'length;
            R_v.Ila          := cmd.Ila;
            R_v.Tid          := cmd.Tid;
            R_v.Addr         := cmd.Ext & cmd.Addr;
            R_v.Len          := cmd.Len;
            return R_v;
        end function;

        procedure request (
            cmd       : TbCmd_t;
            ra        : t_slv_array;
            data      : t_slv_array;
            msg       : string;
            expectCmd : boolean := true) is
            variable R_v : IniReq_t;
        begin
            R_v := toReq(cmd, ra);
            if data'length > 0 then
                axistream_transmit(AXISTREAM_VVCT, VvcData_c, data, msg & ": data");
            end if;
            if expectCmd then
                axistream_expect(AXISTREAM_VVCT, VvcCmd_c, omapPacket(tbCommand(withRa(cmd, ra), data)), msg);
            end if;
            wait until rising_edge(Clk);
            Req <= R_v;

            loop
                wait until rising_edge(Clk);
                exit when ReqReady = '1';
            end loop;

            Req.Valid <= '0';
        end procedure;

        -- A reply as it arrives at the Initiator: without the Reply SpaceWire Address
        function arrived (
            bytes : t_slv_array;
            cmd   : TbCmd_t) return t_slv_array is
            constant Path_c : natural := tbReplyPath(cmd)'length;
            variable Res_v  : t_slv_array(0 to bytes'length - Path_c - 1)(7 downto 0);
        begin

            for i in 0 to Res_v'length - 1 loop
                Res_v(i) := bytes(bytes'low + Path_c + i);
            end loop;

            return Res_v;
        end function;

        function wrRep (
            cmd    : TbCmd_t;
            status : std_logic_vector(7 downto 0)) return t_slv_array is
        begin
            return arrived(tbWriteReply(cmd, status), cmd);
        end function;

        function rdRep (
            cmd    : TbCmd_t;
            status : std_logic_vector(7 downto 0);
            len    : natural;
            data   : t_slv_array) return t_slv_array is
        begin
            return arrived(tbReadReply(cmd, status, len, data), cmd);
        end function;

        -- Read reply of cmd (no Reply Address) with another instruction byte and a correct Header CRC
        function rdRepInstr (
            cmd   : TbCmd_t;
            instr : std_logic_vector(7 downto 0)) return t_slv_array is
            variable Res_v : t_slv_array(0 to 16)(7 downto 0);
        begin
            Res_v     := rdRep(cmd, x"00", 4, tbBytes(4));
            Res_v(2)  := instr;
            Res_v(11) := tbCrc(Res_v(0 to 10));
            return Res_v;
        end function;

        -- Injects a reply packet
        procedure reply (
            bytes : t_slv_array;
            eep   : boolean := false) is
        begin
            axistream_transmit(AXISTREAM_VVCT, VvcRep_c, omapPacket(bytes, eep), "reply");
        end procedure;

        -- Waits for confirmation number n (counted from the start of the test) and checks it
        procedure checkConf (
            n      : natural;
            tid    : natural;
            instr  : std_logic_vector(7 downto 0);
            status : std_logic_vector(7 downto 0);
            len    : natural;
            err    : std_logic_vector(1 downto 0);
            msg    : string) is
            variable Start_v : time;
        begin
            Start_v := now;

            while Obs.ConfCnt < Cnt_v + n + 1 and now < Start_v + 200 us loop
                wait until rising_edge(Clk);
            end loop;

            if Obs.ConfCnt < Cnt_v + n + 1 then
                alert(ERROR, msg & ": confirmation missing");
            else
                check_value(Obs.Conf(Cnt_v + n).Tid, std_logic_vector(to_unsigned(tid, 16)), error, msg & ": TID");
                check_value(Obs.Conf(Cnt_v + n).Instr, instr, error, msg & ": instruction");
                check_value(Obs.Conf(Cnt_v + n).Status, status, error, msg & ": status");
                check_value(Obs.Conf(Cnt_v + n).Len, std_logic_vector(to_unsigned(len, 24)), error, msg & ": length");
                check_value(Obs.Conf(Cnt_v + n).Error, err, error, msg & ": local error");
            end if;
        end procedure;

        -- No further confirmation for 2 us
        procedure checkNoConf (
            total : natural;
            msg   : string) is
        begin
            wait for 2 us;
            check_value(Obs.ConfCnt, Cnt_v + total, error, msg & ": no confirmation");
        end procedure;

        procedure waitIdle is
        begin
            await_completion(AXISTREAM_VVCT, VvcData_c, 1 ms, "data sent");
            await_completion(AXISTREAM_VVCT, VvcCmd_c, 1 ms, "commands received");
            await_completion(AXISTREAM_VVCT, VvcRep_c, 1 ms, "replies sent");
            await_completion(AXISTREAM_VVCT, VvcRepData_c, 1 ms, "reply data received");
        end procedure;

        -- Reply instruction of a command
        function repInstr (cmd : TbCmd_t) return std_logic_vector is
        begin
            return "00" & cmd.Instr(5 downto 0);
        end function;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);

        for i in VvcData_c to VvcRepData_c loop
            disable_log_msg(AXISTREAM_VVCT, i, ALL_MESSAGES);
        end loop;

        while test_suite loop

            Rst   <= '1';
            wait for 100 ns;
            wait until rising_edge(Clk);
            Rst   <= '0';
            wait for 100 ns;
            Cnt_v := Obs.ConfCnt;

            if run("test_commands") then
                -- TC-IN-01: commands of ECSS Annex A.4 and of every command code
                Cmd_v      := tbCmd(x"6C", 0, 16, 0);
                Cmd_v.Addr := x"A0000000";
                request(Cmd_v, tbBytes(0),
                        tbCat(tbCat(tbCat(tbCat(tbOne(x"01"), tbOne(x"23")), tbCat(tbOne(x"45"), tbOne(x"67"))),
                                    tbCat(tbCat(tbOne(x"89"), tbOne(x"AB")), tbCat(tbOne(x"CD"), tbOne(x"EF")))),
                              tbBytes(8, 16#10#)),
                        "Annex A.4 write command");
                Cmd_v      := tbCmd(x"4C", 0, 16, 1);
                Cmd_v.Addr := x"A0000000";
                request(Cmd_v, tbBytes(0), tbBytes(0), "Annex A.4 read command");
                -- Target SpaceWire Address of 7 bytes, Reply Address of 7 bytes padded to 8
                Cmd_v         := tbCmd(x"6C", 0, 16, 2);
                Cmd_v.Addr    := x"A0000010";
                Cmd_v.PathLen := 7;
                Cmd_v.Path    := x"000000000000000000" & x"77665544332211";
                request(Cmd_v,
                        tbCat(tbCat(tbCat(tbOne(x"99"), tbOne(x"AA")), tbCat(tbOne(x"BB"), tbOne(x"CC"))),
                              tbCat(tbCat(tbOne(x"DD"), tbOne(x"EE")), tbOne(x"00"))),
                        tbBytes(16, 16#A0#), "Annex A.4 write command with addresses");
                Cmd_v         := tbCmd(x"4C", 0, 16, 3);
                Cmd_v.Addr    := x"A0000010";
                Cmd_v.PathLen := 4;
                Cmd_v.Path    := x"000000000000000000000000" & x"44332211";
                request(Cmd_v, tbCat(tbCat(tbOne(x"99"), tbOne(x"AA")), tbCat(tbOne(x"BB"), tbOne(x"CC"))), tbBytes(0),
                        "Annex A.4 read command with addresses");
                waitIdle;
                -- Every command code, Reply Address of 1, 5 and 12 bytes, zero-length write
                Rst <= '1';
                wait until rising_edge(Clk);
                Rst <= '0';
                wait until rising_edge(Clk);

                for code in 0 to 15 loop
                    Cmd_v     := tbCmd("01" & std_logic_vector(to_unsigned(code, 4)) & "00", 16#1234# + code, 5, 100 + code);
                    Cmd_v.Ext := x"0" & std_logic_vector(to_unsigned(code, 4));
                    Cmd_v.Key := std_logic_vector(to_unsigned(16 * code, 8));
                    if cmdKind(std_logic_vector(to_unsigned(code, 4))) = CmdRmw then
                        Cmd_v.Len := x"000004";
                        request(Cmd_v, tbBytes(code mod 13), tbBytes(4, code), "command code " & to_string(code));
                    elsif cmdKind(std_logic_vector(to_unsigned(code, 4))) = CmdWrite then
                        request(Cmd_v, tbBytes(code mod 13), tbBytes(5, code), "command code " & to_string(code));
                    else
                        request(Cmd_v, tbBytes(code mod 13), tbBytes(0), "command code " & to_string(code));
                    end if;
                    -- Replies of the commands with reply free the table
                    if Cmd_v.Instr(InstrReply_c) = '1' then
                        reply(wrRep(withRa(Cmd_v, tbBytes(code mod 13)), x"00"));
                    end if;
                end loop;

                Cmd_v := tbCmd(x"7C", 16#40#, 0, 200);
                request(Cmd_v, tbOne(x"00"), tbBytes(0), "zero-length verified write, Reply Address 0x00");
                waitIdle;
                check_value(Obs.CmdSentCnt, 21, error, "commands sent");

            elsif run("test_replies") then
                -- TC-IN-02: replies confirmed, read data passed on
                Cmd_v := tbCmd(x"6C", 16#100#, 4, 10);
                request(Cmd_v, tbBytes(0), tbBytes(4), "write");
                reply(wrRep(Cmd_v, x"00"));
                checkConf(0, 10, repInstr(Cmd_v), x"00", 0, "00", "write reply");
                Cmd_v := tbCmd(x"4C", 16#100#, 16, 11);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 16");
                reply(rdRep(Cmd_v, x"00", 16, tbBytes(16, 5)));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(16, 5), "read data");
                checkConf(1, 11, repInstr(Cmd_v), x"00", 16, "00", "read reply");
                Cmd_v := tbCmd(InstrRmw_c, 16#100#, 8, 12);
                request(Cmd_v, tbBytes(0), tbBytes(8), "read-modify-write");
                reply(rdRep(Cmd_v, x"00", 4, tbBytes(4, 9)));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(4, 9), "read-modify-write data");
                checkConf(2, 12, repInstr(Cmd_v), x"00", 4, "00", "read-modify-write reply");
                Cmd_v := tbCmd(x"4C", 16#100#, 0, 13);
                request(Cmd_v, tbBytes(0), tbBytes(0), "zero-length read");
                reply(rdRep(Cmd_v, x"00", 0, tbBytes(0)));
                checkConf(3, 13, repInstr(Cmd_v), x"00", 0, "00", "zero-length read reply");
                -- Error status codes are confirmed with the status
                Cmd_v := tbCmd(x"6C", 16#100#, 4, 14);
                request(Cmd_v, tbBytes(0), tbBytes(4), "write with an error status");
                reply(wrRep(Cmd_v, StatusKey_c));
                checkConf(4, 14, repInstr(Cmd_v), StatusKey_c, 0, "00", "write reply with status 3");
                Cmd_v := tbCmd(x"4C", 16#100#, 8, 15);
                request(Cmd_v, tbBytes(4, 1), tbBytes(0), "read with Reply Address");
                reply(rdRep(withRa(Cmd_v, tbBytes(4, 1)), StatusNotAuth_c, 0, tbBytes(0)));
                checkConf(5, 15, x"0D", StatusNotAuth_c, 0, "00", "read reply with status 10");
                waitIdle;
                check_value(Obs.RepOkCnt, 6, error, "replies confirmed");

            elsif run("test_reply_errors") then
                -- TC-IN-03: corrupted replies
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 20);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 20");
                -- Header errors: no confirmation (ECSS 5.4.3.11)
                reply(tbCat(tbCat(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4)), 11), tbOne(x"55")), tbBytes(5)));
                reply(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4)), 6));
                reply(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4)), 9), eep => true);
                -- ECSS 5.4.3.13: reserved bit set, command bit set; reply bit clear
                reply(rdRepInstr(Cmd_v, x"8C"));
                reply(rdRepInstr(Cmd_v, x"4C"));
                reply(rdRepInstr(Cmd_v, x"04"));
                checkNoConf(0, "header errors");
                check_value(Obs.HdrErrCnt, 6, error, "header errors counted");
                -- Data errors: confirmation with the local error (ECSS 5.4.3.12)
                reply(tbCat(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), 16), tbOne(not tbCrc(tbBytes(4, 7)))));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(4, 7), "data with a Data CRC error");
                checkConf(0, 20, x"0C", x"00", 4, "01", "Data CRC error");
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 21);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 21");
                reply(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), 15));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(2, 7), "short reply: the last byte is the Data CRC");
                checkConf(1, 21, x"0C", x"00", 4, "01", "short reply");
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 22);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 22");
                reply(tbCat(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), tbBytes(2)));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(4, 7), "long reply");
                checkConf(2, 22, x"0C", x"00", 4, "01", "long reply");
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 23);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 23");
                reply(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), 14), eep => true);
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(1, 7), "EEP in the data: the last byte is the Data CRC");
                checkConf(3, 23, x"0C", x"00", 4, "01", "EEP in the data");
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 24);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 24");
                reply(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), eep => true);
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(4, 7), "EEP after the Data CRC");
                checkConf(4, 24, x"0C", x"00", 4, "01", "EEP after the Data CRC");
                Cmd_v := tbCmd(x"4C", 16#100#, 4, 25);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 25");
                reply(tbHead(rdRep(Cmd_v, x"00", 4, tbBytes(4, 7)), 12));
                checkConf(5, 25, x"0C", x"00", 4, "01", "reply ending after the Header CRC: no data");
                -- Write reply with excess data or EEP (ECSS 5.3.3.11)
                Cmd_v := tbCmd(x"6C", 16#100#, 1, 40);
                request(Cmd_v, tbBytes(0), tbBytes(1), "write");
                reply(tbCat(wrRep(Cmd_v, x"00"), tbBytes(1)));
                checkConf(6, 40, x"2C", x"00", 0, "01", "write reply with excess data");
                Cmd_v := tbCmd(x"6C", 16#100#, 1, 41);
                request(Cmd_v, tbBytes(0), tbBytes(1), "write");
                reply(wrRep(Cmd_v, x"00"), eep => true);
                checkConf(7, 41, x"2C", x"00", 0, "01", "write reply with EEP");
                waitIdle;
                check_value(Obs.DataErrCnt, 8, error, "data errors counted");

            elsif run("test_table") then
                -- TC-IN-04: transaction table (four entries)
                Cmd_v := tbCmd(x"4C", 16#100#, 2, 50);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read 50");
                -- Unknown TID and wrong instruction: discarded
                reply(rdRep(tbCmd(x"4C", 16#100#, 2, 51), x"00", 2, tbBytes(2)));
                reply(rdRep(tbCmd(x"48", 16#100#, 2, 50), x"00", 2, tbBytes(2)));
                checkNoConf(0, "unexpected replies");
                check_value(Obs.UnexpCnt, 2, error, "unexpected replies counted");
                -- TID in use: rejected, not sent, data consumed
                request(tbCmd(x"6C", 16#200#, 3, 50), tbBytes(0), tbBytes(3), "write with TID 50 in use", expectCmd => false);
                checkConf(0, 50, x"6C", x"00", 0, "11", "TID in use");
                check_value(Obs.CmdSentCnt, 1, error, "rejected command not sent");
                check_value(Obs.TidBusyCnt, 1, error, "rejection counted");
                -- Commands without reply are not registered
                request(tbCmd(x"64", 16#300#, 2, 50), tbBytes(0), tbBytes(2), "write without reply, TID 50");
                -- Rejection held by the user, data of the rejected request late
                Cfg.ConfReady <= '0';
                request(tbCmd(x"6C", 16#200#, 3, 50), tbBytes(0), tbBytes(0), "TID 50 in use, held", expectCmd => false);
                wait for 1 us;
                check_value(Obs.ConfValid, '1', error, "rejection held");
                check_value(Obs.ConfCnt, Cnt_v + 1, error, "rejection not taken");
                Cfg.ConfReady <= '1';
                checkConf(1, 50, x"6C", x"00", 0, "11", "TID in use, held");
                wait for 500 ns;
                axistream_transmit(AXISTREAM_VVCT, VvcData_c, tbBytes(3), "late data of the rejected request");
                await_completion(AXISTREAM_VVCT, VvcData_c, 1 ms, "late data consumed");
                request(tbCmd(x"4C", 16#200#, 3, 50), tbBytes(0), tbBytes(0), "read with TID 50 in use", expectCmd => false);
                checkConf(2, 50, x"4C", x"00", 0, "11", "read with TID in use");

                -- Full table: requests wait
                for i in 1 to 3 loop
                    request(tbCmd(x"4C", 16#100#, 2, 50 + i), tbBytes(0), tbBytes(0), "read " & to_string(50 + i));
                end loop;

                wait for 200 ns;
                check_value(Obs.OpenCnt, 4, error, "four commands outstanding");
                check_value(ReqReady, '1', error, "idle encoder ready");
                axistream_expect(AXISTREAM_VVCT, VvcCmd_c, omapPacket(tbCommand(tbCmd(x"4C", 16#100#, 2, 60), tbBytes(0))),
                                 "fifth read");
                Req       <= IniReqInit_c;
                Req.Valid <= '1';
                Req.Code  <= "0011";
                Req.Tid   <= x"003C";
                Req.Addr  <= x"0000000100";
                Req.Len   <= x"000002";
                wait for 1 us;
                check_value(Obs.CmdSentCnt, 5, error, "fifth read waits for a free entry");
                reply(rdRep(tbCmd(x"4C", 16#100#, 2, 52), x"00", 2, tbBytes(2)));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(2), "data of 52");
                checkConf(3, 52, x"0C", x"00", 2, "00", "reply 52");

                loop
                    wait until rising_edge(Clk);
                    exit when ReqReady = '1';
                end loop;

                Req.Valid <= '0';
                waitIdle;
                check_value(Obs.CmdSentCnt, 6, error, "fifth read sent after the reply");
                check_value(Obs.OpenCnt, 4, error, "four commands outstanding");

            elsif run("test_timeout") then
                -- TC-IN-05: reply timeout of 20 ticks of 100 ns
                Cfg.Timeout <= std_logic_vector(to_unsigned(20, 16));
                wait until rising_edge(Clk);
                Cmd_v       := tbCmd(x"4C", 16#100#, 2, 70);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read without reply");
                T_v         := now;
                checkConf(0, 70, x"4C", x"00", 0, "10", "timeout");
                check_value(now - T_v >= 1.9 us and now - T_v <= 2.3 us, error, "timeout after 20 ticks: " & to_string(now - T_v));
                wait for 50 ns;
                check_value(Obs.TimeoutCnt, 1, error, "timeout counted");
                check_value(Obs.OpenCnt, 0, error, "entry removed");
                -- Late reply: unexpected
                reply(rdRep(Cmd_v, x"00", 2, tbBytes(2)));
                checkNoConf(1, "late reply");
                check_value(Obs.UnexpCnt, 1, error, "late reply counted as unexpected");
                -- Reply before the timeout
                Cmd_v := tbCmd(x"6C", 16#100#, 1, 71);
                request(Cmd_v, tbBytes(0), tbBytes(1), "write");
                reply(wrRep(Cmd_v, x"00"));
                checkConf(1, 71, x"2C", x"00", 0, "00", "reply in time");
                checkNoConf(2, "no timeout after the reply");
                wait for 3 us;
                check_value(Obs.TimeoutCnt, 1, error, "no further timeout");
                -- Confirmations held by the user: the reply that came first, then the timeout; the command of the
                -- held reply does not time out
                Cfg.ConfReady <= '0';
                request(tbCmd(x"4C", 16#100#, 2, 73), tbBytes(0), tbBytes(0), "read without reply");
                Cmd_v         := tbCmd(x"6C", 16#100#, 1, 74);
                request(Cmd_v, tbBytes(0), tbBytes(1), "write");
                wait for 1 us;
                reply(wrRep(Cmd_v, x"00"));
                wait for 3 us;
                check_value(Obs.ConfValid, '1', error, "reply held");
                Cfg.ConfReady <= '1';
                checkConf(2, 74, x"2C", x"00", 0, "00", "held reply");
                checkConf(3, 73, x"4C", x"00", 0, "10", "held timeout");
                checkNoConf(4, "no timeout of the confirmed command");
                Cfg.ConfReady <= '0';
                request(tbCmd(x"4C", 16#100#, 2, 75), tbBytes(0), tbBytes(0), "read without reply");
                wait for 3 us;
                check_value(Obs.ConfValid, '1', error, "timeout held");
                Cfg.ConfReady <= '1';
                checkConf(4, 75, x"4C", x"00", 0, "10", "held timeout alone");
                -- Timeout 0: no timeout
                Cfg.Timeout <= x"0000";
                Cmd_v       := tbCmd(x"6C", 16#100#, 1, 72);
                request(Cmd_v, tbBytes(0), tbBytes(1), "write without timeout");
                wait for 10 us;
                check_value(Obs.TimeoutCnt, 3, error, "no timeout with timeout 0");
                check_value(Obs.OpenCnt, 1, error, "entry kept");

            elsif run("test_no_table") then
                -- TC-IN-06: without transaction table (configuration no_table)
                reply(wrRep(tbCmd(x"6C", 0, 0, 80), x"00"));
                checkConf(0, 80, x"2C", x"00", 0, "00", "reply without command");
                request(tbCmd(x"4C", 16#100#, 2, 81), tbBytes(0), tbBytes(0), "read 81");
                request(tbCmd(x"4C", 16#100#, 2, 81), tbBytes(0), tbBytes(0), "read 81 again");
                check_value(Obs.TidBusyCnt, 0, error, "no duplicate check");
                waitIdle;

            elsif run("test_reset") then

                -- TC-IN-08: reset at every cycle of a request in three situations, the Initiator works after each
                -- reset
                for kind in 0 to 2 loop

                    for k in 1 to 80 loop
                        Cfg.DropCmd <= '1';
                        if kind = 1 then
                            -- Rejection held by the user
                            request(tbCmd(x"4C", 16#100#, 4, 1), tbBytes(0), tbBytes(0), "read", expectCmd => false);
                            Cfg.ConfReady <= '0';
                        elsif kind = 2 then

                            -- Full table: the request waits for a free entry
                            for i in 1 to Transactions_g loop
                                request(tbCmd(x"4C", 16#100#, 4, 10 + i), tbBytes(0), tbBytes(0), "read", expectCmd => false);
                            end loop;

                        end if;
                        -- Write with a Target SpaceWire Address of three bytes and 40 data bytes
                        Cmd_v                   := tbCmd(x"6C", 16#100#, 40, 1);
                        Cmd_v.PathLen           := 3;
                        Cmd_v.Path(23 downto 0) := x"030201";
                        axistream_transmit(AXISTREAM_VVCT, VvcData_c, tbBytes(40, k), "data");
                        wait until rising_edge(Clk);
                        Req                     <= toReq(Cmd_v, tbBytes(0));

                        for i in 1 to k loop
                            wait until rising_edge(Clk);
                            if ReqReady = '1' then
                                Req.Valid <= '0';
                            end if;
                        end loop;

                        Rst           <= '1';
                        Req.Valid     <= '0';
                        Cfg.DropData  <= '1';
                        await_completion(AXISTREAM_VVCT, VvcData_c, 1 ms, "rest of the data dropped");
                        wait until rising_edge(Clk);
                        Rst           <= '0';
                        Cfg.DropData  <= '0';
                        Cfg.ConfReady <= '1';
                        wait until rising_edge(Clk);
                        if k mod 10 = 0 then
                            Cfg.DropCmd <= '0';
                            request(tbCmd(x"64", 16#200#, 4, 99), tbBytes(0), tbBytes(4, k), "write after a reset");
                            await_completion(AXISTREAM_VVCT, VvcCmd_c, 1 ms, "command after a reset");
                        end if;
                    end loop;

                end loop;

                Cfg.DropCmd <= '0';
                Cnt_v       := Obs.ConfCnt;
                Cmd_v       := tbCmd(x"4C", 16#100#, 2, 98);
                request(Cmd_v, tbBytes(0), tbBytes(0), "read after the resets");
                reply(rdRep(Cmd_v, x"00", 2, tbBytes(2)));
                axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(2), "read data after the resets");
                checkConf(0, 98, x"0C", x"00", 2, "00", "read after the resets");
                waitIdle;

            elsif run("test_stress") then
                -- TC-IN-07: backpressure on every stream, commands and replies interleaved
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.ready_low_at_word_num              := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.ready_low_duration                 := C_RANDOM;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.ready_low_max_random_duration      := 8;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.ready_low_multiple_random_prob     := 0.3;
                shared_axistream_vvc_config(VvcRepData_c).bfm_config.ready_low_at_word_num          := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcRepData_c).bfm_config.ready_low_duration             := C_RANDOM;
                shared_axistream_vvc_config(VvcRepData_c).bfm_config.ready_low_max_random_duration  := 8;
                shared_axistream_vvc_config(VvcRepData_c).bfm_config.ready_low_multiple_random_prob := 0.3;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.valid_low_at_word_num              := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.valid_low_duration                 := C_RANDOM;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.valid_low_max_random_duration      := 8;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.valid_low_multiple_random_prob     := 0.3;
                shared_axistream_vvc_config(VvcData_c).bfm_config.valid_low_at_word_num             := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcData_c).bfm_config.valid_low_duration                := C_RANDOM;
                shared_axistream_vvc_config(VvcData_c).bfm_config.valid_low_max_random_duration     := 8;
                shared_axistream_vvc_config(VvcData_c).bfm_config.valid_low_multiple_random_prob    := 0.3;

                for i in 0 to 29 loop
                    if i mod 2 = 0 then
                        Cmd_v := tbCmd(x"6C", 16#1000# + i, 50 + i, 1000 + i);
                        request(Cmd_v, tbBytes(i mod 9), tbBytes(50 + i, i), "write " & to_string(i));
                        reply(wrRep(withRa(Cmd_v, tbBytes(i mod 9)), x"00"));
                    else
                        Cmd_v := tbCmd(x"4C", 16#1000# + i, 100 + i, 1000 + i);
                        request(Cmd_v, tbBytes(0), tbBytes(0), "read " & to_string(i));
                        reply(rdRep(Cmd_v, x"00", 100 + i, tbBytes(100 + i, i)));
                        axistream_expect(AXISTREAM_VVCT, VvcRepData_c, tbBytes(100 + i, i), "data " & to_string(i));
                    end if;
                end loop;

                waitIdle;
                checkConf(29, 1029, x"0C", x"00", 129, "00", "last confirmation");
                wait for 50 ns;
                check_value(Obs.RepOkCnt, 30, error, "30 replies confirmed");
            end if;

        end loop;

        omapTestEnd(runner);
    end process;

    i_th : entity work.omap_initiator_th
        generic map (
            Transactions_g => Transactions_g
        )
        port map (
            Clk      => Clk,
            Rst      => Rst,
            Req      => Req,
            Cfg      => Cfg,
            Obs      => Obs,
            ReqReady => ReqReady
        );

end architecture;
