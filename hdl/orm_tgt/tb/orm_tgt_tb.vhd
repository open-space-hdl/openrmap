---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the RMAP target: commands built by the RMAP model, replies compared byte by byte with
-- the replies of the model, memory compared through the backdoor of the AXI memory model.
--
-- Documentation: hdl/orm_tgt/docs/verification_plan.md

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
    use work.orm_pkg.all;
    use work.orm_tb_pkg.all;
    use work.orm_tb_rmap_pkg.all;
    use work.orm_tb_memvar_pkg.all;
    use work.orm_tgt_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_tgt_tb is
    generic (
        runner_cfg     : string;
        AxiDataWidth_g : positive := 32;
        Windows_g      : natural  := 4;
        ExtAuth_g      : boolean  := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of orm_tgt_tb is

    constant Word_c : positive := AxiDataWidth_g / 8;

    signal Clk : std_logic;
    signal Rst : std_logic := '1';
    signal Cfg : TgtCfg_t  := TgtCfgInit_c;
    signal Obs : TgtObs_t;

begin

    test_runner_watchdog(runner, 20 ms);

    p_main : process is
        variable Cmd_v   : TbCmd_t;
        variable Cnt_v   : natural;
        variable Sent_v  : natural;
        variable Data_v  : t_slv_array(0 to 4095)(7 downto 0);
        variable Old_v   : t_slv_array(0 to 3)(7 downto 0);
        variable Exp_v   : std_logic_vector(7 downto 0);
        variable Addr_v  : natural;
        variable Len_v   : natural;
        variable Instr_v : std_logic_vector(7 downto 0);

        -- Sends a command packet (bytes and end of packet marker)
        procedure send (
            bytes : t_slv_array;
            eep   : boolean := false) is
        begin
            axistream_transmit(AXISTREAM_VVCT, VvcCmd_c, ormPacket(bytes, eep), "command");
        end procedure;

        -- Expects a reply packet
        procedure expect (
            bytes : t_slv_array;
            msg   : string;
            eep   : boolean := false) is
        begin
            axistream_expect(AXISTREAM_VVCT, VvcRep_c, ormPacket(bytes, eep), msg);
        end procedure;

        -- Waits until both VVCs are idle and the target has indicated n more commands
        procedure finish (
            n   : natural;
            msg : string) is
            variable Start_v : time;
        begin
            await_completion(AXISTREAM_VVCT, VvcCmd_c, 10 ms, "commands sent");
            await_completion(AXISTREAM_VVCT, VvcRep_c, 10 ms, "replies received");
            Start_v := now;

            while Obs.IndCnt < Cnt_v + n and now < Start_v + 100 us loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Obs.IndCnt, Cnt_v + n, error, msg & ": indications");
            Cnt_v := Obs.IndCnt;
        end procedure;

        -- No reply is sent for 3 us
        procedure checkNoReply (msg : string) is
        begin
            wait for 3 us;
            check_value(Obs.RepValid, '0', error, msg & ": no reply");
            check_value(Obs.RepSentCnt, Sent_v, error, msg & ": no reply sent");
        end procedure;

        -- Status and reply flag of the last indication
        procedure checkInd (
            status  : std_logic_vector(7 downto 0);
            replied : std_logic;
            msg     : string) is
        begin
            check_value(Obs.IndStatus, status, error, msg & ": status");
            check_value(Obs.IndReplied, replied, error, msg & ": reply sent");
            Sent_v := Obs.RepSentCnt;
        end procedure;

        -- Memory content from addr
        procedure checkMem (
            addr : natural;
            data : t_slv_array;
            msg  : string) is
            variable Ok_v : boolean := true;
        begin

            for i in 0 to data'length - 1 loop
                if Mem_v.read8(0, addr + i) /= data(data'low + i) then
                    Ok_v := false;
                    alert(ERROR, msg & ": memory byte " & to_string(i) & " at 0x" &
                          to_hstring(to_unsigned(addr + i, 16)) & " is 0x" & to_hstring(Mem_v.read8(0, addr + i)) &
                          ", expected 0x" & to_hstring(data(data'low + i)));
                    exit;
                end if;
            end loop;

        end procedure;

        -- Memory bytes as a byte array
        impure function memBytes (
            addr : natural;
            n    : natural) return t_slv_array is
            variable Res_v : t_slv_array(0 to n - 1)(7 downto 0);
        begin

            for i in 0 to n - 1 loop
                Res_v(i) := Mem_v.read8(0, addr + i);
            end loop;

            return Res_v;
        end function;

        -- Write command with reply; checks the reply status
        procedure writeCmd (
            instr  : std_logic_vector(7 downto 0);
            addr   : natural;
            data   : t_slv_array;
            status : std_logic_vector(7 downto 0);
            msg    : string) is
            variable C_v : TbCmd_t;
        begin
            C_v := tbCmd(instr, addr, data'length, addr mod 65536);
            send(tbCommand(C_v, data));
            if instr(InstrReply_c) = '1' then
                expect(tbWriteReply(C_v, status), msg);
            end if;
            finish(1, msg);
            checkInd(status, instr(InstrReply_c), msg);
        end procedure;

        -- Read command; checks the reply with the memory content
        procedure readCmd (
            instr : std_logic_vector(7 downto 0);
            addr  : natural;
            len   : natural;
            data  : t_slv_array;
            msg   : string) is
            variable C_v : TbCmd_t;
        begin
            C_v := tbCmd(instr, addr, len, 1000 + addr mod 1000);
            send(tbCommand(C_v, tbBytes(0)));
            expect(tbReadReply(C_v, x"00", len, data), msg);
            finish(1, msg);
            checkInd(x"00", '1', msg);
        end procedure;

        -- Rejected command; checks the reply status and that the memory is untouched
        procedure rejectCmd (
            c      : TbCmd_t;
            data   : t_slv_array;
            status : std_logic_vector(7 downto 0);
            msg    : string) is
        begin
            Mem_v.clearStats(0);
            send(tbCommand(c, data));
            if cmdKind(cmdCode(c.Instr)) = CmdRead or cmdKind(cmdCode(c.Instr)) = CmdRmw then
                expect(tbReadReply(c, status, 0, tbBytes(0)), msg);
            else
                expect(tbWriteReply(c, status), msg);
            end if;
            finish(1, msg);
            checkInd(status, '1', msg);
            check_value(Mem_v.bytesWritten(0), 0, error, msg & ": nothing written");
            check_value(Mem_v.beatsRead(0), 0, error, msg & ": nothing read");
        end procedure;

        -- Error injection strobe of one cycle (set after a clock edge so that the target samples it once)
        procedure inject (
            channels : std_logic_vector(2 downto 0);
            double   : std_logic) is
        begin
            wait until rising_edge(Clk);
            Cfg.ErrInj    <= channels;
            Cfg.ErrDouble <= double;
            wait until rising_edge(Clk);
            Cfg.ErrInj    <= "000";
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        disable_log_msg(AXISTREAM_VVCT, VvcCmd_c, ALL_MESSAGES);
        disable_log_msg(AXISTREAM_VVCT, VvcRep_c, ALL_MESSAGES);

        while test_suite loop

            Rst    <= '1';
            wait for 100 ns;
            wait until rising_edge(Clk);
            Rst    <= '0';
            wait for 100 ns;
            Cnt_v  := Obs.IndCnt;
            Sent_v := Obs.RepSentCnt;

            if run("test_annex_patterns") then
                -- TC-TG-01: ECSS Annex A.4 commands give the replies of Annex A.4
                Cmd_v           := tbCmd(x"6C", 0, 16, 0);
                Cmd_v.Addr      := x"A0000000";
                Data_v(0 to 15) := (x"01",
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
                send(tbCommand(Cmd_v, Data_v(0 to 15)));
                expect(tbWriteReply(Cmd_v, x"00"), "write reply of Annex A.4");
                finish(1, "write");
                checkMem(0, Data_v(0 to 15), "written data");
                Cmd_v           := tbCmd(x"4C", 0, 16, 1);
                Cmd_v.Addr      := x"A0000000";
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 16, Data_v(0 to 15)), "read reply of Annex A.4");
                finish(1, "read");
                -- With Reply Address (the Target SpaceWire Address is removed before the target)
                Cmd_v           := tbCmd(x"6E", 0, 16, 2);
                Cmd_v.Addr      := x"A0000010";
                Cmd_v.ReplyAddr := x"00000000" & x"00EEDDCCBBAA9900";
                send(tbCommand(Cmd_v, tbBytes(16, 16#A0#)));
                expect(tbWriteReply(Cmd_v, x"00"), "write reply with Reply SpaceWire Address");
                finish(1, "write with Reply Address");
                checkMem(16#10#, tbBytes(16, 16#A0#), "written data");
                Cmd_v           := tbCmd(x"4D", 0, 16, 3);
                Cmd_v.Addr      := x"A0000010";
                Cmd_v.ReplyAddr := x"0000000000000000" & x"CCBBAA99";
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 16, tbBytes(16, 16#A0#)), "read reply with Reply SpaceWire Address");
                finish(1, "read with Reply Address");
                check_value(Obs.IndInstr, x"4D", error, "indicated instruction");
                check_value(Obs.IndTid, x"0003", error, "indicated Transaction Identifier");
                check_value(Obs.IndAddr, x"00A0000010", error, "indicated address");
                check_value(Obs.IndLen, x"000010", error, "indicated length");
                check_value(Obs.IndIla, x"67", error, "indicated Initiator Logical Address");
                check_value(Obs.IndTla, x"FE", error, "indicated Target Logical Address");

            elsif run("test_write_variants") then

                -- TC-TG-02: the eight write commands, incrementing and single address, lengths up to 1000
                for code in 8 to 15 loop
                    Instr_v := "01" & std_logic_vector(to_unsigned(code, 4)) & "00";
                    if Instr_v(InstrInc_c) = '1' then

                        for k in 0 to 4 loop

                            case k is
                                when 0 => Len_v := 1;
                                when 1 => Len_v := 7;
                                when 2 => Len_v := 100;
                                when 3 => Len_v := 256;
                                when others => Len_v := 1000;
                            end case;

                            if Instr_v(InstrVerify_c) = '0' or Len_v <= 256 then
                                Addr_v := 16#1000# * code + 16#100# * k + (k mod 4);
                                Mem_v.clearStats(0);
                                writeCmd(Instr_v, Addr_v, tbBytes(Len_v, code + k), x"00",
                                         "write 0x" & to_hstring(Instr_v) & " length " & to_string(Len_v));
                                checkMem(Addr_v, tbBytes(Len_v, code + k), "write 0x" & to_hstring(Instr_v));
                                check_value(Mem_v.bytesWritten(0), Len_v, error, "bytes written");
                                check_value(Mem_v.lowestWritten(0), Addr_v, error, "lowest address written");
                                check_value(Mem_v.highestWritten(0), Addr_v + Len_v - 1, error, "highest address written");
                            end if;
                        end loop;

                    else
                        -- ECSS 5.3.3.6.14a: single address, every word to the same address
                        Addr_v := 16#1000# * code + 16#800#;
                        Mem_v.clearStats(0);
                        writeCmd(Instr_v, Addr_v, tbBytes(3 * Word_c, code), x"00",
                                 "write 0x" & to_hstring(Instr_v));
                        checkMem(Addr_v, tbBytes(Word_c, code + 2 * Word_c), "last word at the single address");
                        check_value(Mem_v.bytesWritten(0), 3 * Word_c, error, "three words written");
                        check_value(Mem_v.highestWritten(0), Addr_v + Word_c - 1, error, "only the word at the address");
                    end if;
                end loop;

                -- ECSS 5.3.1.12 note: zero length, nothing written
                Mem_v.clearStats(0);
                writeCmd(x"6C", 16#40#, tbBytes(0), x"00", "zero-length write");
                writeCmd(x"7C", 16#40#, tbBytes(0), x"00", "zero-length verified write");
                check_value(Mem_v.bytesWritten(0), 0, error, "zero-length writes write nothing");

            elsif run("test_read_variants") then
                -- TC-TG-03: incrementing and single-address reads
                Mem_v.fill(0, 0, 8192, 7);
                readCmd(x"4C", 16#100#, 0, tbBytes(0), "zero-length read");
                readCmd(x"4C", 16#101#, 1, memBytes(16#101#, 1), "read 1 byte");
                readCmd(x"4C", 16#203#, 3, memBytes(16#203#, 3), "read 3 bytes");
                readCmd(x"4C", 16#305#, 64, memBytes(16#305#, 64), "read 64 bytes");
                readCmd(x"4C", 16#3FF#, 1000, memBytes(16#3FF#, 1000), "read 1000 bytes");
                readCmd(x"4F", 16#1F00#, 300, memBytes(16#1F00#, 300), "read with RAL 3");
                -- ECSS 5.4.3.6b: single address, the same word for every word of the reply
                readCmd(x"48", 16#800#, 3 * Word_c,
                        tbCat(tbCat(memBytes(16#800#, Word_c), memBytes(16#800#, Word_c)), memBytes(16#800#, Word_c)),
                        "single-address read");
                check_value(Obs.IndStatus, x"00", error, "status");

            elsif run("test_rmw") then
                -- TC-TG-04: read-modify-write of 1 to 4 bytes, the reply returns the data read
                Mem_v.fill(0, 0, 256, 16#30#);

                for n in 1 to 4 loop
                    Addr_v            := 16#20# * n + n - 1;
                    Old_v(0 to n - 1) := memBytes(Addr_v, n);
                    Cmd_v             := tbCmd(InstrRmw_c, Addr_v, 2 * n, 500 + n);
                    -- Data 0x5A.., mask 0x0F..: written = (mask and data) or (not mask and read)
                    Data_v(0 to 2 * n - 1) := tbCat(tbBytes(n, 16#5A#), tbBytes(n, 16#0F#));
                    send(tbCommand(Cmd_v, Data_v(0 to 2 * n - 1)));
                    expect(tbReadReply(Cmd_v, x"00", n, Old_v(0 to n - 1)), "read-modify-write reply of " & to_string(n));
                    finish(1, "read-modify-write of " & to_string(n));
                    checkInd(x"00", '1', "read-modify-write");

                    for i in 0 to n - 1 loop
                        Exp_v := (Data_v(n + i) and Data_v(i)) or (not Data_v(n + i) and Old_v(i));
                        check_value(Mem_v.read8(0, Addr_v + i), Exp_v, error, "modified byte " & to_string(i));
                    end loop;

                    check_value(Mem_v.read8(0, Addr_v + n), std_logic_vector(to_unsigned(16#30# + Addr_v + n, 8)),
                                error, "byte after the modified ones unchanged");
                end loop;

                -- ECSS Figure 5-16: data 0x88, mask 0x8E, read 0xE3, written 0xE9
                Mem_v.write8(0, 16#90#, x"E3");
                Cmd_v := tbCmd(InstrRmw_c, 16#90#, 2, 600);
                send(tbCommand(Cmd_v, tbCat(tbOne(x"88"), tbOne(x"8E"))));
                expect(tbReadReply(Cmd_v, x"00", 1, tbOne(x"E3")), "Figure 5-16 reply");
                finish(1, "Figure 5-16");
                check_value(Mem_v.read8(0, 16#90#), x"E9", error, "Figure 5-16 written data");
                -- Zero bytes: reply without data, no memory access
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(InstrRmw_c, 16#90#, 0, 601);
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 0, tbBytes(0)), "zero-length read-modify-write");
                finish(1, "zero-length read-modify-write");
                check_value(Mem_v.beatsRead(0) + Mem_v.bytesWritten(0), 0, error, "no memory access");

            elsif run("test_header_errors") then
                -- TC-TG-05: header errors discard the packet without reply
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"6C", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(4), hdrCrcErr => true));
                checkNoReply("Header CRC error");
                check_value(Obs.HdrCrcCnt, 1, error, "Header CRC error counted");
                Cmd_v := tbCmd(x"4C", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(0), hdrCrcErr => true));
                checkNoReply("Header CRC error of a read");
                check_value(Obs.HdrCrcCnt, 2, error, "Header CRC errors counted");

                -- ECSS 5.3.3.4.2: end of the packet before the Header CRC, with EOP and with EEP
                for n in 2 to 15 loop
                    send(tbHead(tbCommand(Cmd_v, tbBytes(0)), n), eep => n mod 2 = 1);
                end loop;

                checkNoReply("incomplete headers");
                check_value(Obs.HdrShortCnt, 14, error, "incomplete headers counted");

                -- ECSS 5.3.3.4.3: EEP immediately after the Header CRC
                Cmd_v := tbCmd(x"6C", 16#100#, 4);
                send(tbHead(tbCommand(Cmd_v, tbBytes(4)), 16), eep => true);
                finish(1, "EEP after a write header");
                checkInd(StatusEep_c, '0', "EEP after a write header");
                Cmd_v := tbCmd(x"4C", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(0)), eep => true);
                finish(1, "EEP after a read header");
                checkInd(StatusEep_c, '0', "EEP after a read header");
                Cmd_v := tbCmd(InstrRmw_c, 16#100#, 2);
                send(tbHead(tbCommand(Cmd_v, tbBytes(2)), 16), eep => true);
                finish(1, "EEP after a read-modify-write header");
                checkInd(StatusEep_c, '0', "EEP after a read-modify-write header");
                checkNoReply("EEP after the header");
                -- ECSS 5.7.1.3b: a reply at the target is discarded
                send(tbWriteReply(tbCmd(x"6C"), x"00"));
                checkNoReply("reply at the target");
                check_value(Obs.ReplyRxCnt, 1, error, "reply at the target counted");
                -- ECSS 5.3.3.4.6: reserved packet types are discarded without reply
                Cmd_v := tbCmd(x"AC", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(4), forceData => true));
                finish(1, "packet type 0b10");
                checkInd(StatusUnused_c, '0', "packet type 0b10");
                Cmd_v := tbCmd(x"CC", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(0)));
                finish(1, "packet type 0b11");
                checkInd(StatusUnused_c, '0', "packet type 0b11");
                checkNoReply("reserved packet types");
                -- ECSS 5.3.3.4.1: other Protocol Identifiers are not decoded
                Cmd_v     := tbCmd(x"6C", 16#100#, 4);
                Cmd_v.Pid := x"02";
                send(tbCommand(Cmd_v, tbBytes(4)));
                checkNoReply("Protocol Identifier 2");
                check_value(Obs.IndCnt, Cnt_v, error, "no command indicated");
                check_value(Mem_v.bytesWritten(0) + Mem_v.beatsRead(0), 0, error, "no memory access");

            elsif run("test_invalid_codes") then

                -- TC-TG-06: invalid command codes (ECSS Table 5-1)
                for code in 0 to 6 loop
                    if code /= 2 and code /= 3 then
                        Instr_v := "01" & std_logic_vector(to_unsigned(code, 4)) & "00";
                        Cmd_v   := tbCmd(Instr_v, 16#100#, 4, code);
                        send(tbCommand(Cmd_v, tbBytes(0)));
                        if Instr_v(InstrReply_c) = '1' then
                            -- Code 0b0110 has the reply bit set
                            expect(tbWriteReply(Cmd_v, StatusUnused_c), "invalid code 0b0110");
                        end if;
                        finish(1, "invalid code " & to_string(code));
                        checkInd(StatusUnused_c, Instr_v(InstrReply_c), "invalid code " & to_string(code));
                    end if;
                end loop;

            elsif run("test_authorisation") then
                -- TC-TG-07: logical address, key, windows, permissions, alignment, lengths
                Cfg.DefLaEn <= '0';
                Cfg.La1En   <= '1';
                Cfg.Key     <= x"20";
                wait until rising_edge(Clk);
                Cmd_v       := tbCmd(x"6C", 16#100#, 4);
                rejectCmd(Cmd_v, tbBytes(4), StatusTla_c, "default address 0xFE disabled");
                Cmd_v.Tla   := x"42";
                rejectCmd(Cmd_v, tbBytes(4), StatusKey_c, "key 0x00 instead of 0x20");
                Cmd_v.Key   := x"20";
                send(tbCommand(Cmd_v, tbBytes(4)));
                expect(tbWriteReply(Cmd_v, x"00"), "logical address 0x42 and key 0x20");
                finish(1, "logical address 0x42 and key 0x20");
                Cmd_v       := tbCmd(x"6C", 16#100#, 4, 7);
                Cmd_v.Tla   := x"43";
                Cmd_v.Key   := x"20";
                send(tbCommand(Cmd_v, tbBytes(4)));
                expect(tbWriteReply(Cmd_v, x"00"), "second logical address 0x43");
                finish(1, "second logical address");
                Cfg.KeyEn   <= '0';
                Cfg.La1En   <= '0';
                wait until rising_edge(Clk);
                Cmd_v.Key   := x"99";
                rejectCmd(Cmd_v, tbBytes(4), StatusTla_c, "second logical address disabled");
                Cmd_v.Tla   := x"42";
                send(tbCommand(Cmd_v, tbBytes(4)));
                expect(tbWriteReply(Cmd_v, x"00"), "key check disabled");
                finish(1, "key check disabled");
                -- Priority (architecture D9): invalid code before logical address before key
                Cmd_v.Tla   := x"77";
                Cmd_v.Instr := x"58";
                rejectCmd(Cmd_v, tbBytes(0), StatusUnused_c, "invalid code and wrong logical address");
                Cfg.DefLaEn <= '1';
                Cfg.KeyEn   <= '1';
                Cfg.Key     <= x"00";
                -- Windows: 0 read and write 0x1000 to 0x1FFF, 1 verified writes only 0x2000 to 0x20FF,
                -- 2 read-modify-write 0x3000 to 0x30FF, 3 single-address read and write 0x4000 to 0x400F
                Cfg.Win(0) <= tbWin("11000", x"0000001000", x"0000001FFF");
                Cfg.Win(1) <= tbWin("01100", x"0000002000", x"00000020FF");
                Cfg.Win(2) <= tbWin("00010", x"0000003000", x"00000030FF");
                Cfg.Win(3) <= tbWin("11001", x"0000004000", x"000000400F");
                wait until rising_edge(Clk);
                writeCmd(x"6C", 16#1000#, tbBytes(16), x"00", "write in window 0");
                writeCmd(x"6C", 16#1FFC#, tbBytes(4), x"00", "write at the end of window 0");
                rejectCmd(tbCmd(x"6C", 16#1FFD#, 4), tbBytes(4), StatusNotAuth_c, "write across the end of window 0");
                rejectCmd(tbCmd(x"6C", 16#0FFF#, 2), tbBytes(2), StatusNotAuth_c, "write across the start of window 0");
                rejectCmd(tbCmd(InstrRmw_c, 16#1000#, 2), tbBytes(2), StatusNotAuth_c, "read-modify-write in window 0");
                rejectCmd(tbCmd(x"68", 16#1000#, 4), tbBytes(4), StatusNotAuth_c, "single-address write in window 0");
                rejectCmd(tbCmd(x"6C", 16#2000#, 4), tbBytes(4), StatusNotAuth_c, "non-verified write in window 1");
                writeCmd(x"7C", 16#2000#, tbBytes(4), x"00", "verified write in window 1");
                rejectCmd(tbCmd(x"4C", 16#2000#, 4), tbBytes(0), StatusNotAuth_c, "read in window 1");
                rejectCmd(tbCmd(x"6C", 16#3000#, 4), tbBytes(4), StatusNotAuth_c, "write in window 2");
                Cmd_v      := tbCmd(InstrRmw_c, 16#3000#, 8, 9);
                send(tbCommand(Cmd_v, tbBytes(8)));
                expect(tbReadReply(Cmd_v, x"00", 4, memBytes(16#3000#, 4)), "read-modify-write in window 2");
                finish(1, "read-modify-write in window 2");
                writeCmd(x"68", 16#4000#, tbBytes(2 * Word_c), x"00", "single-address write in window 3");
                rejectCmd(tbCmd(x"68", 16#4000# + 1, Word_c), tbBytes(Word_c), StatusNotAuth_c,
                          "single-address write not aligned");
                rejectCmd(tbCmd(x"68", 16#4000#, Word_c + 1), tbBytes(Word_c + 1), StatusNotAuth_c,
                          "single-address write length not a multiple of the word");
                rejectCmd(tbCmd(x"4C", 16#5000#, 4), tbBytes(0), StatusNotAuth_c, "read outside every window");
                -- Address above the AXI address range (32 bits)
                Cfg.Win(0) <= WinOpen_c;
                wait until rising_edge(Clk);
                Cmd_v      := tbCmd(x"4C", 16#100#, 4);
                Cmd_v.Ext  := x"01";
                rejectCmd(Cmd_v, tbBytes(0), StatusNotAuth_c, "Extended Address above the AXI range");
                Cmd_v      := tbCmd(x"4C", 0, 4);
                Cmd_v.Addr := x"FFFFFFFE";
                rejectCmd(Cmd_v, tbBytes(0), StatusNotAuth_c, "read across the end of the AXI range");
                -- ECSS 5.5.3.4.13: read-modify-write lengths
                rejectCmd(tbCmd(InstrRmw_c, 16#100#, 3), tbBytes(3), StatusRmwLength_c, "read-modify-write length 3");
                rejectCmd(tbCmd(InstrRmw_c, 16#100#, 10), tbBytes(10), StatusRmwLength_c, "read-modify-write length 10");
                -- ECSS 5.3.3.6.3: verify buffer
                rejectCmd(tbCmd(x"7C", 16#100#, 257), tbBytes(257), StatusVerifyOverrun_c, "verified write of 257 bytes");
                -- Priority: key before read-modify-write length before verify buffer
                Cmd_v     := tbCmd(InstrRmw_c, 16#100#, 3);
                Cmd_v.Key := x"01";
                rejectCmd(Cmd_v, tbBytes(3), StatusKey_c, "wrong key and read-modify-write length");

            elsif run("test_verified_errors") then
                -- TC-TG-08: a verified write with an error writes nothing
                Cmd_v := tbCmd(x"7C", 16#100#, 16);
                Mem_v.clearStats(0);
                send(tbCommand(Cmd_v, tbBytes(16), dataCrcErr => true));
                expect(tbWriteReply(Cmd_v, StatusDataCrc_c), "Data CRC error");
                finish(1, "Data CRC error");
                send(tbHead(tbCommand(Cmd_v, tbBytes(16)), 30));
                expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "early EOP");
                finish(1, "early EOP");
                send(tbCat(tbCommand(Cmd_v, tbBytes(16)), tbBytes(3)));
                expect(tbWriteReply(Cmd_v, StatusTooMuch_c), "too much data");
                finish(1, "too much data");
                send(tbCommand(Cmd_v, tbBytes(16)), eep => true);
                expect(tbWriteReply(Cmd_v, StatusEep_c), "EEP after the Data CRC");
                finish(1, "EEP after the Data CRC");
                send(tbHead(tbCommand(Cmd_v, tbBytes(16)), 20), eep => true);
                expect(tbWriteReply(Cmd_v, StatusEep_c), "EEP in the data");
                finish(1, "EEP in the data");
                -- Priority: EEP before Data CRC error
                send(tbCommand(Cmd_v, tbBytes(16), dataCrcErr => true), eep => true);
                expect(tbWriteReply(Cmd_v, StatusEep_c), "EEP and Data CRC error");
                finish(1, "EEP and Data CRC error");
                check_value(Mem_v.bytesWritten(0), 0, error, "no byte written");
                -- Verified write without reply: status in the indication
                Cmd_v := tbCmd(x"74", 16#100#, 16);
                send(tbCommand(Cmd_v, tbBytes(16), dataCrcErr => true));
                finish(1, "Data CRC error without reply");
                checkInd(StatusDataCrc_c, '0', "Data CRC error without reply");
                check_value(Mem_v.bytesWritten(0), 0, error, "no byte written");

            elsif run("test_unverified_errors") then
                -- TC-TG-09: a non-verified write is written in chunks of 32 bytes while it arrives
                Cmd_v := tbCmd(x"6C", 16#100#, 100);
                Mem_v.clearStats(0);
                send(tbCommand(Cmd_v, tbBytes(100), dataCrcErr => true));
                expect(tbWriteReply(Cmd_v, StatusDataCrc_c), "Data CRC error");
                finish(1, "Data CRC error");
                checkMem(16#100#, tbBytes(100), "data written despite the Data CRC error");
                -- Early EOP after 70 data bytes: two complete chunks (64 bytes) written, the rest not
                Mem_v.fill(0, 16#400#, 100, 200);
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"6C", 16#400#, 100);
                send(tbHead(tbCommand(Cmd_v, tbBytes(100, 9)), 16 + 70));
                expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "early EOP");
                finish(1, "early EOP");
                checkMem(16#400#, tbBytes(64, 9), "complete chunks written");
                checkMem(16#440#, tbBytes(36, 200 + 64), "incomplete chunk not written");
                check_value(Mem_v.bytesWritten(0), 64, error, "64 bytes written");
                -- EEP after 40 data bytes: one chunk written
                Mem_v.fill(0, 16#600#, 100, 50);
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"6C", 16#600#, 100);
                send(tbHead(tbCommand(Cmd_v, tbBytes(100, 3)), 16 + 40), eep => true);
                expect(tbWriteReply(Cmd_v, StatusEep_c), "EEP");
                finish(1, "EEP");
                check_value(Mem_v.bytesWritten(0), 32, error, "32 bytes written");
                checkMem(16#620#, tbBytes(68, 50 + 32), "rest not written");
                -- Too much data: the Data Length bytes are written
                Mem_v.fill(0, 16#800#, 64, 0);
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"6C", 16#800#, 50);
                send(tbCat(tbCommand(Cmd_v, tbBytes(50, 5)), tbBytes(10, 99)));
                expect(tbWriteReply(Cmd_v, StatusTooMuch_c), "too much data");
                finish(1, "too much data");
                check_value(Mem_v.bytesWritten(0), 50, error, "50 bytes written");
                checkMem(16#800#, tbBytes(50, 5), "Data Length bytes written");
                -- Early EOP of a short write: the Data CRC byte is not written as data
                Mem_v.fill(0, 16#900#, 16, 0);
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"6C", 16#900#, 8);
                send(tbCommand(tbCmd(x"6C", 16#900#, 8), tbBytes(4)));
                expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "4 of 8 bytes and a Data CRC");
                finish(1, "short write");
                check_value(Mem_v.bytesWritten(0), 0, error, "incomplete chunk not written");

            elsif run("test_read_rmw_end_errors") then
                -- TC-TG-10: end of the packet of reads and read-modify-writes
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(x"4C", 16#100#, 8);
                send(tbCat(tbCommand(Cmd_v, tbBytes(0)), tbBytes(1)));
                expect(tbReadReply(Cmd_v, StatusTooMuch_c, 0, tbBytes(0)), "data after a read header");
                finish(1, "data after a read header");
                send(tbCat(tbCommand(Cmd_v, tbBytes(0)), tbBytes(2)), eep => true);
                expect(tbReadReply(Cmd_v, StatusEep_c, 0, tbBytes(0)), "data and EEP after a read header");
                finish(1, "data and EEP after a read header");
                check_value(Mem_v.beatsRead(0), 0, error, "read not executed");
                Cmd_v := tbCmd(InstrRmw_c, 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(4), dataCrcErr => true));
                expect(tbReadReply(Cmd_v, StatusDataCrc_c, 0, tbBytes(0)), "read-modify-write Data CRC error");
                finish(1, "read-modify-write Data CRC error");
                send(tbHead(tbCommand(Cmd_v, tbBytes(4)), 18));
                expect(tbReadReply(Cmd_v, StatusEarlyEop_c, 0, tbBytes(0)), "read-modify-write early EOP");
                finish(1, "read-modify-write early EOP");
                send(tbCat(tbCommand(Cmd_v, tbBytes(4)), tbBytes(1)));
                expect(tbReadReply(Cmd_v, StatusTooMuch_c, 0, tbBytes(0)), "read-modify-write too much data");
                finish(1, "read-modify-write too much data");
                send(tbHead(tbCommand(Cmd_v, tbBytes(4)), 18), eep => true);
                expect(tbReadReply(Cmd_v, StatusEep_c, 0, tbBytes(0)), "read-modify-write EEP");
                finish(1, "read-modify-write EEP");
                check_value(Mem_v.beatsRead(0) + Mem_v.bytesWritten(0), 0, error, "no memory access");

            elsif run("test_memory_errors") then
                -- TC-TG-11: error responses of the memory
                Mem_v.fill(0, 0, 4096, 1);
                Mem_v.setWriteError(0, 16#200#, 16#20F#);
                Mem_v.setReadError(0, 16#300#, 16#30F#);
                writeCmd(x"6C", 16#1F0#, tbBytes(64), StatusGeneral_c, "write into an error range");
                writeCmd(x"7C", 16#200#, tbBytes(4), StatusGeneral_c, "verified write into an error range");
                -- ECSS 5.4.3.10c.1: read reply ended by an EEP
                Cmd_v := tbCmd(x"4C", 16#2F0#, 64);
                send(tbCommand(Cmd_v, tbBytes(0)));
                axistream_expect(AXISTREAM_VVCT, VvcRep_c,
                                 ormPacket(tbReadReply(Cmd_v, x"00", 64, memBytes(16#2F0#, 64), noCrc => true), true),
                                 "read reply ended by an EEP");
                finish(1, "read error");
                checkInd(StatusGeneral_c, '1', "read error");
                -- Read-modify-write: read error, nothing written
                Mem_v.clearStats(0);
                Cmd_v := tbCmd(InstrRmw_c, 16#304#, 4);
                send(tbCommand(Cmd_v, tbBytes(4)));
                expect(tbReadReply(Cmd_v, StatusGeneral_c, 2, tbBytes(0)), "read-modify-write read error");
                finish(1, "read-modify-write read error");
                check_value(Mem_v.bytesWritten(0), 0, error, "nothing written after a read error");
                -- Read-modify-write: write error, the data read is returned
                Cmd_v := tbCmd(InstrRmw_c, 16#208#, 4);
                send(tbCommand(Cmd_v, tbBytes(4)));
                expect(tbReadReply(Cmd_v, StatusGeneral_c, 2, memBytes(16#208#, 2)), "read-modify-write write error");
                finish(1, "read-modify-write write error");
                -- Normal operation afterwards
                Mem_v.setWriteError(0, 1, 0);
                Mem_v.setReadError(0, 1, 0);
                writeCmd(x"6C", 16#200#, tbBytes(16), x"00", "write after the errors");
                readCmd(x"4C", 16#300#, 16, memBytes(16#300#, 16), "read after the errors");

            elsif run("test_ext_auth") then
                -- TC-TG-12: external authorisation (configuration ext_auth)
                writeCmd(x"6C", 16#100#, tbBytes(8), x"00", "accepted write");
                check_value(Obs.AuthCnt, 1, error, "one request");
                check_value(Obs.AuthInstr, x"6C", error, "request instruction");
                check_value(Obs.AuthAddr, x"0000000100", error, "request address");
                check_value(Obs.AuthLen, x"000008", error, "request length");
                Cfg.AuthAccept <= '0';
                wait until rising_edge(Clk);
                rejectCmd(tbCmd(x"6C", 16#100#, 8), tbBytes(8), StatusNotAuth_c, "rejected write");
                rejectCmd(tbCmd(x"4C", 16#100#, 8), tbBytes(0), StatusNotAuth_c, "rejected read");
                rejectCmd(tbCmd(InstrRmw_c, 16#100#, 2), tbBytes(2), StatusNotAuth_c, "rejected read-modify-write");
                -- Priority: EEP and Data CRC error before the rejection
                Cmd_v := tbCmd(x"6C", 16#100#, 8);
                send(tbCommand(Cmd_v, tbBytes(8)), eep => true);
                expect(tbWriteReply(Cmd_v, StatusEep_c), "rejected write with EEP");
                finish(1, "rejected write with EEP");
                -- ECSS 5.5.3.4.8: read-modify-write data is checked before the authorisation is requested
                Cnt_v          := Obs.IndCnt;
                Sent_v         := Obs.AuthCnt;
                Cmd_v          := tbCmd(InstrRmw_c, 16#100#, 2);
                send(tbCommand(Cmd_v, tbBytes(2), dataCrcErr => true));
                expect(tbReadReply(Cmd_v, StatusDataCrc_c, 0, tbBytes(0)), "read-modify-write Data CRC error");
                finish(1, "read-modify-write Data CRC error");
                check_value(Obs.AuthCnt, Sent_v, error, "no request for a read-modify-write with a Data CRC error");
                Cfg.AuthAccept <= '1';
                wait until rising_edge(Clk);
                Mem_v.write8(0, 16#100#, x"F0");
                Cmd_v          := tbCmd(InstrRmw_c, 16#100#, 2);
                send(tbCommand(Cmd_v, tbCat(tbOne(x"0F"), tbOne(x"0F"))));
                expect(tbReadReply(Cmd_v, x"00", 1, tbOne(x"F0")), "accepted read-modify-write");
                finish(1, "accepted read-modify-write");
                check_value(Mem_v.read8(0, 16#100#), x"FF", error, "modified byte");
                readCmd(x"4C", 16#100#, 1, tbOne(x"FF"), "accepted read");

            elsif run("test_reply_address") then
                -- TC-TG-13: Reply SpaceWire Address (ECSS 5.1.6c to e, Table 5-3)
                Cmd_v           := tbCmd(x"4D", 16#100#, 0, 1);
                Cmd_v.ReplyAddr := x"0000000000000000" & x"00000000";
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 0, tbBytes(0)), "all zero: a single 0x00");
                Cmd_v.ReplyAddr := x"0000000000000000" & x"02000100";
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 0, tbBytes(0)), "0x00 0x01 0x00 0x02");
                Cmd_v.ReplyAddr := x"0000000000000000" & x"00020100";
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 0, tbBytes(0)), "0x00 0x01 0x02 0x00");
                Cmd_v           := tbCmd(x"6E", 16#100#, 1, 2);
                Cmd_v.ReplyAddr := x"00000000" & x"0504030201000000";
                send(tbCommand(Cmd_v, tbBytes(1)));
                expect(tbWriteReply(Cmd_v, x"00"), "eight bytes with three leading zeros");
                Cmd_v           := tbCmd(x"6F", 16#100#, 1, 3);
                Cmd_v.ReplyAddr := x"0C0B0A090807060504030201";
                send(tbCommand(Cmd_v, tbBytes(1)));
                expect(tbWriteReply(Cmd_v, x"00"), "twelve bytes");
                finish(5, "Reply Addresses");

            elsif run("test_stress") then
                -- TC-TG-14: backpressure on every interface, long transfers, commands back to back
                Mem_v.setStall(0, 40);
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_at_word_num          := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_duration             := C_RANDOM;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_max_random_duration  := 10;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_multiple_random_prob := 0.2;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_at_word_num          := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_duration             := C_RANDOM;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_max_random_duration  := 10;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_multiple_random_prob := 0.2;
                -- 4 kB write across a 4 kB boundary, read back
                Cmd_v := tbCmd(x"6C", 16#0F80#, 4096, 1);
                send(tbCommand(Cmd_v, tbBytes(4096, 11)));
                expect(tbWriteReply(Cmd_v, x"00"), "4 kB write");
                Cmd_v := tbCmd(x"4C", 16#0F80#, 4096, 2);
                send(tbCommand(Cmd_v, tbBytes(0)));
                expect(tbReadReply(Cmd_v, x"00", 4096, tbBytes(4096, 11)), "4 kB read");
                finish(2, "4 kB");

                -- 40 commands of all kinds back to back
                for i in 0 to 39 loop
                    Addr_v := 16#3000# + 64 * i + i mod 4;

                    case i mod 4 is

                        when 0 =>
                            Cmd_v := tbCmd(x"6C", Addr_v, 33, i);
                            send(tbCommand(Cmd_v, tbBytes(33, i)));
                            expect(tbWriteReply(Cmd_v, x"00"), "write " & to_string(i));

                        when 1 =>
                            Cmd_v := tbCmd(x"7C", Addr_v, 20, i);
                            send(tbCommand(Cmd_v, tbBytes(20, i)));
                            expect(tbWriteReply(Cmd_v, x"00"), "verified write " & to_string(i));

                        when 2 =>
                            Cmd_v := tbCmd(x"4C", 16#3000# + 64 * (i - 2), 33, i);
                            send(tbCommand(Cmd_v, tbBytes(0)));
                            expect(tbReadReply(Cmd_v, x"00", 33, tbBytes(33, i - 2)), "read " & to_string(i));

                        when others =>
                            Cmd_v := tbCmd(x"64", Addr_v, 7, i);
                            send(tbCommand(Cmd_v, tbBytes(7, i)));

                    end case;

                end loop;

                finish(40, "commands back to back");

            elsif run("test_ecc") then
                -- TC-TG-15: errors in the data buffers
                inject("001", '0');
                writeCmd(x"7C", 16#100#, tbBytes(8), x"00", "single error in the write buffer");
                checkMem(16#100#, tbBytes(8), "corrected data");
                check_value(Obs.SecCnt, 1, error, "single error counted");
                inject("001", '1');
                writeCmd(x"7C", 16#200#, tbBytes(8), StatusGeneral_c, "double error in the write buffer");
                check_value(Obs.DedCnt, 1, error, "double error counted");
                inject("010", '1');
                writeCmd(x"6C", 16#300#, tbBytes(8), StatusGeneral_c, "double error in the write data of the master");
                check_value(Obs.DedCnt, 2, error, "double errors counted");
                Mem_v.fill(0, 16#400#, 16, 3);
                inject("100", '1');
                Cmd_v := tbCmd(x"4C", 16#400#, 16);
                send(tbCommand(Cmd_v, tbBytes(0)));
                await_completion(AXISTREAM_VVCT, VvcCmd_c, 1 ms, "command");
                axistream_receive(AXISTREAM_VVCT, VvcRep_c, "reply with a double error in the read data");
                await_completion(AXISTREAM_VVCT, VvcRep_c, 1 ms, "reply");
                finish(1, "double error in the read data of the master");
                checkInd(StatusGeneral_c, '1', "double error in the read data");
                check_value(Obs.DedCnt, 3, error, "double errors counted");
            end if;

        end loop;

        ormTestEnd(runner);
    end process;

    i_th : entity work.orm_tgt_th
        generic map (
            AxiDataWidth_g => AxiDataWidth_g,
            Windows_g      => Windows_g,
            ExtAuth_g      => ExtAuth_g
        )
        port map (
            Clk => Clk,
            Rst => Rst,
            Cfg => Cfg,
            Obs => Obs
        );

end architecture;
