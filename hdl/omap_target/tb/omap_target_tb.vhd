---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the RMAP Target: commands built by the RMAP model, replies compared byte by byte with
-- the replies of the model, memory compared through the backdoor of the AXI memory model.
--
-- Documentation: hdl/omap_target/docs/verification_plan.md

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
    use work.omap_tb_memvar_pkg.all;
    use work.omap_target_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_target_tb is
    generic (
        runner_cfg     : string;
        AxiAddrWidth_g : positive := 32;
        AxiDataWidth_g : positive := 32;
        BufferBytes_g  : positive := 256;
        Windows_g      : natural  := 4;
        ExtAuth_g      : boolean  := false;
        ChunkBytes_g   : positive := 32;
        AxiMaxBeats_g  : positive := 16
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of omap_target_tb is

    constant Word_c : positive := AxiDataWidth_g / 8;

    signal Clk : std_logic;
    signal Rst : std_logic := '1';
    signal Cfg : TgtCfg_t  := TgtCfgInit_c;
    signal Obs : TgtObs_t;

begin

    test_runner_watchdog(runner, 20 ms);

    p_main : process is
        variable Cmd_v    : TbCmd_t;
        variable Cnt_v    : natural;
        variable Sent_v   : natural;
        variable Data_v   : t_slv_array(0 to 4095)(7 downto 0);
        variable Old_v    : t_slv_array(0 to 3)(7 downto 0);
        variable Exp_v    : std_logic_vector(7 downto 0);
        variable Addr_v   : natural;
        variable Len_v    : natural;
        variable Instr_v  : std_logic_vector(7 downto 0);
        variable Lat_v    : natural;
        variable Cyc_v    : integer_vector(1 to 2);
        variable Cyc2_v   : integer_vector(1 to 2);
        variable WrRate_v : real;

        -- Lengths at the end of a 12-bit address space
        constant SpaceLen_c : integer_vector := (1023, 1024, 4095, 4096);

        -- Memory latencies of the rate and timing tests
        constant RateLat_c : integer_vector := (0, 20, 40, 80, 160);

        -- Bytes of a write transaction: a chunk is one command of the AXI master, split into bursts
        constant WrTf_c : positive := minimum(ChunkBytes_g, Word_c * AxiMaxBeats_g);

        -- Sustained memory rates in bytes per cycle (user guide section Performance): the read data buffer of the
        -- AXI master holds two bursts, and the master issues at most one read transaction every four cycles; a write
        -- moves one byte per cycle without a gap between its chunks, and at most four write transactions are open,
        -- each for lat + 5 + WrTf_c/Word_c cycles
        function readRate (lat : natural) return real is
        begin
            return minimum(minimum(1.0, real(Word_c * AxiMaxBeats_g) / 4.0),
                           real(2 * Word_c * AxiMaxBeats_g) / real(lat + 7 + Word_c * (AxiMaxBeats_g - 1)));
        end function;

        function writeRate (lat : natural) return real is
        begin
            return minimum(1.0, real(4 * WrTf_c) / real(lat + 5 + WrTf_c / Word_c));
        end function;

        -- Lower bound of the write rate with single-beat bursts: the AXI master issues the n = ChunkBytes_g/Word_c
        -- transactions of a chunk in at most 4.5n + 3 cycles
        function writeIssueRate return real is
        begin
            if AxiMaxBeats_g = 1 then
                return real(ChunkBytes_g) / (4.5 * real(ChunkBytes_g / Word_c) + 3.0);
            end if;
            return 1.0;
        end function;

        -- Sends a command packet (bytes and end of packet marker)
        procedure send (
            bytes : t_slv_array;
            eep   : boolean := false) is
        begin
            axistream_transmit(AXISTREAM_VVCT, VvcCmd_c, omapPacket(bytes, eep), "command");
        end procedure;

        -- Expects a reply packet
        procedure expect (
            bytes : t_slv_array;
            msg   : string;
            eep   : boolean := false) is
        begin
            axistream_expect(AXISTREAM_VVCT, VvcRep_c, omapPacket(bytes, eep), msg);
        end procedure;

        -- Waits until both VVCs are idle and the Target has indicated n more commands
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

        -- Start offset and length of a command in a message
        function place (
            offset : natural;
            n      : natural) return string is
        begin
            return " at offset " & to_string(offset) & ", " & to_string(n) & " bytes";
        end function;

        -- Clock cycles per command of cnt commands of one kind back to back (0 read, 1 write, 2 read-modify-write
        -- of n bytes with a zero mask): time from the first command to the last indication
        procedure backToBack (
            kind : natural;
            n    : natural;
            cnt  : natural;
            cyc  : out natural) is
            variable C_v : TbCmd_t;
            variable T_v : time;
            variable Z_v : t_slv_array(0 to 3)(7 downto 0) := (others => (others => '0'));
        begin
            T_v := now;

            for i in 1 to cnt loop

                case kind is
                    when 0 =>
                        C_v := tbCmd(x"4C", 16#100#, n, i);
                        send(tbCommand(C_v, tbBytes(0)));
                        expect(tbReadReply(C_v, x"00", n, memBytes(16#100#, n)), "read back to back");
                    when 1 =>
                        C_v := tbCmd(x"6C", 16#100#, n, i);
                        send(tbCommand(C_v, tbBytes(n)));
                        expect(tbWriteReply(C_v, x"00"), "write back to back");
                    when others =>
                        C_v := tbCmd(InstrRmw_c, 16#100#, 2 * n, i);
                        send(tbCommand(C_v, tbCat(tbBytes(n, 16#5A#), Z_v(0 to n - 1))));
                        expect(tbReadReply(C_v, x"00", n, memBytes(16#100#, n)), "read-modify-write back to back");
                end case;

            end loop;

            finish(cnt, "commands back to back");
            cyc := (now - T_v) / 10 ns;
        end procedure;

        -- Period of commands back to back: the difference of 10 and 5 commands
        procedure period (
            kind : natural;
            n    : natural;
            cyc  : out natural) is
            variable C5_v  : natural;
            variable C10_v : natural;
        begin
            backToBack(kind, n, 5, C5_v);
            backToBack(kind, n, 10, C10_v);
            cyc := (C10_v - C5_v) / 5;
        end procedure;

        -- Memory latency and length of a command in a message
        function atLat (
            lat : natural;
            n   : natural) return string is
        begin
            return " with latency " & to_string(lat) & ", " & to_string(n) & " bytes";
        end function;

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

        -- Error injection strobe of one cycle (set after a clock edge so that the Target samples it once)
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
                -- With Reply Address (the Target SpaceWire Address is removed before the Target)
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
                Cmd_v     := tbCmd(x"6C", 16#100#, 4);
                send(tbHead(tbCommand(Cmd_v, tbBytes(4)), 16), eep => true);
                finish(1, "EEP after a write header");
                checkInd(StatusEep_c, '0', "EEP after a write header");
                Cmd_v     := tbCmd(x"4C", 16#100#, 4);
                send(tbCommand(Cmd_v, tbBytes(0)), eep => true);
                finish(1, "EEP after a read header");
                checkInd(StatusEep_c, '0', "EEP after a read header");
                Cmd_v     := tbCmd(InstrRmw_c, 16#100#, 2);
                send(tbHead(tbCommand(Cmd_v, tbBytes(2)), 16), eep => true);
                finish(1, "EEP after a read-modify-write header");
                checkInd(StatusEep_c, '0', "EEP after a read-modify-write header");
                Cmd_v     := tbCmd(x"6C", 16#100#, 4);
                Cmd_v.Key := x"99";
                send(tbHead(tbCommand(Cmd_v, tbBytes(4)), 16), eep => true);
                finish(1, "EEP after the header of a rejected command");
                checkInd(StatusEep_c, '0', "EEP after the header of a rejected command");
                checkNoReply("EEP after the header");
                -- ECSS 5.7.1.3b: a reply at the Target is discarded
                send(tbWriteReply(tbCmd(x"6C"), x"00"));
                checkNoReply("reply at the Target");
                check_value(Obs.ReplyRxCnt, 1, error, "reply at the Target counted");
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
                -- The same with a slow memory: the incomplete chunk is discarded after the complete ones are written
                Mem_v.setStall(0, 85);
                Mem_v.fill(0, 16#400#, 100, 200);
                Mem_v.clearStats(0);
                send(tbHead(tbCommand(Cmd_v, tbBytes(100, 9)), 16 + 70));
                expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "early EOP, slow memory");
                finish(1, "early EOP, slow memory");
                checkMem(16#400#, tbBytes(64, 9), "complete chunks written, slow memory");
                check_value(Mem_v.bytesWritten(0), 64, error, "64 bytes written, slow memory");
                -- Early EOP at a chunk boundary while the memory still writes earlier chunks: all chunks written
                Mem_v.setStall(0, 90);
                Cmd_v := tbCmd(x"6C", 16#400#, 400);

                for n in 3 to 11 loop
                    Mem_v.fill(0, 16#400#, 400, 200);
                    Mem_v.clearStats(0);
                    send(tbHead(tbCommand(Cmd_v, tbBytes(400, 9)), 16 + 32 * n));
                    expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "early EOP at a chunk boundary");
                    finish(1, "early EOP at a chunk boundary");
                    checkMem(16#400#, tbBytes(32 * n, 9), "chunks written, early EOP at a chunk boundary");
                    check_value(Mem_v.bytesWritten(0), 32 * n, error, "bytes written, early EOP at a chunk boundary");
                end loop;

                Mem_v.setStall(0, 0);
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
                                 omapPacket(tbReadReply(Cmd_v, x"00", 64, memBytes(16#2F0#, 64), noCrc => true), true),
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
                send(tbHead(tbCommand(Cmd_v, tbBytes(8)), 20));
                expect(tbWriteReply(Cmd_v, StatusEarlyEop_c), "rejected write with an early EOP");
                finish(1, "rejected write with an early EOP");
                send(tbCat(tbCommand(Cmd_v, tbBytes(8)), tbBytes(2)));
                expect(tbWriteReply(Cmd_v, StatusTooMuch_c), "rejected write with too much data");
                finish(1, "rejected write with too much data");
                send(tbCommand(Cmd_v, tbBytes(8), dataCrcErr => true));
                expect(tbWriteReply(Cmd_v, StatusDataCrc_c), "rejected write with a Data CRC error");
                finish(1, "rejected write with a Data CRC error");
                send(tbCommand(tbCmd(x"64", 16#100#, 8), tbBytes(8)));
                finish(1, "rejected write without reply");
                checkInd(StatusNotAuth_c, '0', "rejected write without reply");
                checkNoReply("rejected write without reply");
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

                -- Write buffer full: a slow memory holds the command stream
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_at_word_num := 0;
                shared_axistream_vvc_config(VvcCmd_c).bfm_config.valid_low_duration    := 0;
                Mem_v.setStall(0, 90);
                Cmd_v                                                                  := tbCmd(x"6C", 16#5000#, 1000, 950);
                send(tbCommand(Cmd_v, tbBytes(1000, 17)));
                expect(tbWriteReply(Cmd_v, x"00"), "write with a full buffer");
                finish(1, "write with a full buffer");
                checkMem(16#5000#, tbBytes(1000, 17), "write with a full buffer");
                Mem_v.setStall(0, 40);

                -- Replies requested while the encoder still sends the previous one
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_at_word_num := 0;
                shared_axistream_vvc_config(VvcRep_c).bfm_config.ready_low_duration    := 40;

                for i in 0 to 2 loop
                    Cmd_v := tbCmd(x"6C", 16#100#, 0, 900 + i);
                    send(tbCommand(Cmd_v, tbBytes(0)));
                    expect(tbWriteReply(Cmd_v, x"00"), "zero-length write " & to_string(i));
                end loop;

                finish(3, "replies back to back");

            elsif run("test_reset") then
                -- TC-TG-16: reset at every cycle of five commands, the Target works after each reset
                Mem_v.fill(0, 0, 4096, 16#20#);
                Cfg.DropRep <= '1';

                for kind in 0 to 4 loop

                    for k in 1 to 140 loop

                        case kind is

                            when 0 =>
                                Cmd_v := tbCmd(x"7C", 16#100#, 40, k);
                                send(tbCommand(Cmd_v, tbBytes(40, k)));

                            when 1 =>
                                Cmd_v := tbCmd(x"6C", 16#200#, 100, k);
                                send(tbCommand(Cmd_v, tbBytes(100, k)));

                            when 2 =>
                                Cmd_v           := tbCmd(x"4D", 16#300#, 64, k);
                                Cmd_v.ReplyAddr := x"0000000000000000" & x"CCBBAA99";
                                send(tbCommand(Cmd_v, tbBytes(0)));

                            when 3 =>
                                Cmd_v := tbCmd(InstrRmw_c, 16#400#, 8, k);
                                send(tbCommand(Cmd_v, tbBytes(8, k)));

                            when others =>
                                Cmd_v     := tbCmd(x"6C", 16#500#, 40, k);
                                Cmd_v.Key := x"99";
                                send(tbCommand(Cmd_v, tbBytes(40, k)));

                        end case;

                        for i in 1 to k loop
                            wait until rising_edge(Clk);
                        end loop;

                        Rst         <= '1';
                        Cfg.DropCmd <= '1';
                        await_completion(AXISTREAM_VVCT, VvcCmd_c, 1 ms, "rest of the command dropped");
                        wait until rising_edge(Clk);
                        Rst         <= '0';
                        Cfg.DropCmd <= '0';
                        wait until rising_edge(Clk);
                        if k mod 20 = 0 then
                            Cfg.DropRep <= '0';
                            Cnt_v       := Obs.IndCnt;
                            readCmd(x"4C", 16#F00#, 4, memBytes(16#F00#, 4), "read after a reset");
                            Cfg.DropRep <= '1';
                        end if;
                    end loop;

                end loop;

                Cfg.DropRep <= '0';
                Cnt_v       := Obs.IndCnt;
                writeCmd(x"7C", 16#F00#, tbBytes(16, 5), x"00", "write after the resets");
                checkMem(16#F00#, tbBytes(16, 5), "write after the resets");

            elsif run("test_burst_split") then
                -- TC-TG-17: commands the AXI master splits into transactions of AxiMaxBeats_g beats, at every start
                -- offset of a memory word, up to two transactions and one word more
                Mem_v.fill(0, 0, 4096, 11);

                for a in 0 to Word_c - 1 loop

                    for n in 1 to (2 * AxiMaxBeats_g + 1) * Word_c + 1 loop
                        readCmd(x"4C", 16#100# + a, n, memBytes(16#100# + a, n), "read" & place(a, n));
                    end loop;

                end loop;

                -- Exactly the addressed bytes written; the bytes around them keep the pattern 200 + i from 0x800
                for a in 0 to Word_c - 1 loop

                    for n in 1 to (2 * AxiMaxBeats_g + 1) * Word_c + 1 loop
                        Mem_v.fill(0, 16#800#, 512, 200);
                        Mem_v.clearStats(0);
                        writeCmd(x"6C", 16#900# + a, tbBytes(n, a + n), x"00", "write" & place(a, n));
                        checkMem(16#800#, tbBytes(16#100# + a, 200), "bytes before the write" & place(a, n));
                        checkMem(16#900# + a, tbBytes(n, a + n), "written bytes" & place(a, n));
                        checkMem(16#900# + a + n, tbBytes(16#100# - a - n, 200 + 16#100# + a + n),
                                 "bytes after the write" & place(a, n));
                        check_value(Mem_v.lowestWritten(0), 16#900# + a, error, "lowest address written" & place(a, n));
                        check_value(Mem_v.highestWritten(0), 16#900# + a + n - 1, error,
                                    "highest address written" & place(a, n));
                    end loop;

                end loop;

                -- Read-modify-write of 1 to 4 bytes, across a word boundary at the last offsets
                for a in 0 to Word_c - 1 loop

                    for n in 1 to 4 loop
                        Addr_v                 := 16#C00# + 16#40# * a + 16#10# * n + a;
                        Old_v(0 to n - 1)      := memBytes(Addr_v, n);
                        Cmd_v                  := tbCmd(InstrRmw_c, Addr_v, 2 * n, 500 + n);
                        Data_v(0 to 2 * n - 1) := tbCat(tbBytes(n, 16#5A#), tbBytes(n, 16#0F#));
                        send(tbCommand(Cmd_v, Data_v(0 to 2 * n - 1)));
                        expect(tbReadReply(Cmd_v, x"00", n, Old_v(0 to n - 1)), "read-modify-write reply" & place(a, n));
                        finish(1, "read-modify-write" & place(a, n));
                        checkInd(x"00", '1', "read-modify-write" & place(a, n));

                        for i in 0 to n - 1 loop
                            Exp_v := (Data_v(n + i) and Data_v(i)) or (not Data_v(n + i) and Old_v(i));
                            check_value(Mem_v.read8(0, Addr_v + i), Exp_v, error,
                                        "modified byte " & to_string(i) & place(a, n));
                        end loop;

                        checkMem(Addr_v - Word_c, tbBytes(Word_c, 11 + Addr_v - Word_c), "word before" & place(a, n));
                        checkMem(Addr_v + n, tbBytes(Word_c, 11 + Addr_v + n), "word after" & place(a, n));
                    end loop;

                end loop;

            elsif run("test_rate") then
                -- TC-TG-18: sustained memory rates; the cycles of 4096 and of 2048 bytes give the rate of 2048 bytes
                Mem_v.fill(0, 16#1000#, 4096, 3);

                for i in RateLat_c'range loop
                    Lat_v := RateLat_c(i);
                    Mem_v.setLatency(0, Lat_v);

                    for k in 1 to 2 loop
                        writeCmd(x"6C", 16#1000#, tbBytes(2048 * k, k), x"00", "long write");
                        Cyc_v(k)  := Obs.RepFirst - Obs.CmdFirst;
                        readCmd(x"4C", 16#1000#, 2048 * k, memBytes(16#1000#, 2048 * k), "long read");
                        Cyc2_v(k) := Obs.RepLast - Obs.RepFirst;
                    end loop;

                    WrRate_v := 2048.0 / real(Cyc_v(2) - Cyc_v(1));
                    log(ID_SEQUENCER, "latency " & to_string(Lat_v) & ": write " & to_string(WrRate_v, 3) & " (" &
                        to_string(minimum(writeRate(Lat_v), writeIssueRate), 3) & "), read " &
                        to_string(2048.0 / real(Cyc2_v(2) - Cyc2_v(1)), 3) & " (" & to_string(readRate(Lat_v), 3) &
                        ") bytes per cycle");

                    if writeIssueRate < writeRate(Lat_v) then
                        -- Single-beat bursts at a low latency: the issue rate of the master is a lower bound
                        check_value(WrRate_v >= writeIssueRate, error, "write rate at latency " & to_string(Lat_v));
                    else
                        check_value(abs(WrRate_v - writeRate(Lat_v)) < 0.01 * writeRate(Lat_v), error,
                                    "write rate at latency " & to_string(Lat_v));
                    end if;

                    check_value(abs(2048.0 / real(Cyc2_v(2) - Cyc2_v(1)) - readRate(Lat_v)) < 0.01 * readRate(Lat_v),
                                error, "read rate at latency " & to_string(Lat_v));
                end loop;

            elsif run("test_timing") then
                -- TC-TG-19: clock cycles of single commands and of commands back to back, memory latency 0 and 20
                Mem_v.fill(0, 0, 4096, 1);

                for i in 0 to 1 loop
                    Lat_v := 20 * i;
                    Mem_v.setLatency(0, Lat_v);

                    for n in 1 to 2 * ChunkBytes_g + 8 loop
                        writeCmd(x"6C", 16#100#, tbBytes(n), x"00", "write");
                        check_value(Obs.CmdLast - Obs.CmdFirst + 1, n + 22, error, "write taken" & atLat(Lat_v, n));
                        if n <= ChunkBytes_g and n <= Word_c * AxiMaxBeats_g then
                            check_value(Obs.RepFirst - Obs.CmdLast, n + (n + Word_c - 1) / Word_c + 19 + Lat_v, error,
                                        "write end to reply" & atLat(Lat_v, n));
                        end if;
                        readCmd(x"4C", 16#101#, n, memBytes(16#101#, n), "read");
                        check_value(Obs.CmdLast - Obs.CmdFirst + 1, 21, error, "read taken" & atLat(Lat_v, n));
                        check_value(Obs.RepFirst - Obs.CmdLast, 5, error, "read end to reply" & atLat(Lat_v, n));
                        check_value(Obs.RepLast - Obs.RepFirst + 1, n + 17 + Word_c + Lat_v, error,
                                    "read reply" & atLat(Lat_v, n));
                    end loop;

                    for n in 1 to 4 loop
                        Old_v(0 to n - 1) := memBytes(16#200#, n);
                        Cmd_v             := tbCmd(InstrRmw_c, 16#200#, 2 * n, 700 + n);
                        send(tbCommand(Cmd_v, tbCat(tbBytes(n, 16#5A#), tbBytes(n, 16#0F#))));
                        expect(tbReadReply(Cmd_v, x"00", n, Old_v(0 to n - 1)), "read-modify-write");
                        finish(1, "read-modify-write");
                        check_value(Obs.CmdLast - Obs.CmdFirst + 1, 2 * n + 22, error, "read-modify-write taken" &
                                    atLat(Lat_v, n));
                        check_value(Obs.RepFirst - Obs.CmdLast, 2 * n + 38 + Word_c + 2 * Lat_v, error,
                                    "read-modify-write end to reply" & atLat(Lat_v, n));
                        check_value(Obs.RepLast - Obs.RepFirst + 1, n + 16, error, "read-modify-write reply" &
                                    atLat(Lat_v, n));
                    end loop;

                    -- Back to back: reads n + 23 + W + L, writes of whole chunks at most n (C + 9) / C + C + 29
                    for n in 0 to 1 loop
                        period(0, 16 + 240 * n, Cyc_v(1));
                        check_value(Cyc_v(1), 16 + 240 * n + 23 + Word_c + Lat_v, error,
                                    "reads back to back" & atLat(Lat_v, 16 + 240 * n));
                        period(1, 2 * ChunkBytes_g + 6 * ChunkBytes_g * n, Cyc_v(2));
                        log(ID_SEQUENCER, "writes back to back" & atLat(Lat_v, 2 * ChunkBytes_g + 6 * ChunkBytes_g * n) &
                            ": " & to_string(Cyc_v(2)) & " cycles");
                        check_value(Cyc_v(2) <= (2 + 6 * n) * (ChunkBytes_g + 9) + ChunkBytes_g + 29 + Lat_v, error,
                                    "writes back to back" & atLat(Lat_v, 2 * ChunkBytes_g + 6 * ChunkBytes_g * n));
                    end loop;

                    period(2, 4, Cyc_v(1));
                    check_value(Cyc_v(1), 76 + Word_c + 2 * Lat_v, error, "read-modify-writes back to back" &
                                atLat(Lat_v, 4));
                end loop;

            elsif run("test_addr_width") then
                -- TC-TG-20: accesses at the ends of the address space; at 12 bits longer than one command of the
                -- memory master (1020 bytes at 32 bits, 2047 at 8 bits)
                if AxiAddrWidth_g = 12 then
                    Mem_v.fill(0, 0, 4096, 9);

                    for k in SpaceLen_c'range loop
                        Len_v := SpaceLen_c(k);
                        Mem_v.clearStats(0);
                        readCmd(x"4C", 0, Len_v, memBytes(0, Len_v), "read of " & to_string(Len_v) & " bytes");
                        check_value(Mem_v.beatsRead(0), (Len_v + Word_c - 1) / Word_c, error,
                                    "beats read for " & to_string(Len_v) & " bytes");
                        Mem_v.clearStats(0);
                        writeCmd(x"6C", 0, tbBytes(Len_v, k), x"00", "write of " & to_string(Len_v) & " bytes");
                        checkMem(0, tbBytes(Len_v, k), "write of " & to_string(Len_v) & " bytes");
                        check_value(Mem_v.bytesWritten(0), Len_v, error, "bytes written of " & to_string(Len_v));
                        check_value(Mem_v.lowestWritten(0), 0, error, "lowest address of " & to_string(Len_v));
                        check_value(Mem_v.highestWritten(0), Len_v - 1, error, "highest address of " &
                                    to_string(Len_v));
                    end loop;

                    -- Beyond the address space: status 10 without memory access (architecture D4)
                    rejectCmd(tbCmd(x"4C", 0, 4097), tbBytes(0), StatusNotAuth_c, "read of 4097 bytes");
                    rejectCmd(tbCmd(x"6C", 0, 4097), tbBytes(4097), StatusNotAuth_c, "write of 4097 bytes");
                    -- Single address over the whole space: every word to and from address 0
                    Mem_v.clearStats(0);
                    writeCmd(x"68", 0, tbBytes(4096, 3), x"00", "single-address write of 4096 bytes");
                    checkMem(0, tbBytes(Word_c, 3 + 4096 - Word_c), "last word at the single address");
                    check_value(Mem_v.bytesWritten(0), 4096, error, "single-address write: bytes written");
                    check_value(Mem_v.highestWritten(0), Word_c - 1, error, "single-address write: only the word");
                    Mem_v.clearStats(0);
                    Cmd_v := tbCmd(x"48", 0, 4096, 77);
                    send(tbCommand(Cmd_v, tbBytes(0)));

                    for i in 0 to 4096 / Word_c - 1 loop
                        Data_v(i * Word_c to i * Word_c + Word_c - 1) := memBytes(0, Word_c);
                    end loop;

                    expect(tbReadReply(Cmd_v, x"00", 4096, Data_v(0 to 4095)), "single-address read of 4096 bytes");
                    finish(1, "single-address read of 4096 bytes");
                    check_value(Mem_v.beatsRead(0), 4096 / Word_c, error, "single-address read: beats read");
                    -- Error response in the second command of a split read: header with status 0, all data, EEP
                    Addr_v := 1500 when Word_c > 1 else 2100;
                    Mem_v.setReadError(0, Addr_v, Addr_v + 3);
                    Cmd_v  := tbCmd(x"4C", 0, 2560, 78);
                    send(tbCommand(Cmd_v, tbBytes(0)));
                    expect(tbReadReply(Cmd_v, x"00", 2560, memBytes(0, 2560), noCrc => true),
                           "split read with an error in its second command", eep => true);
                    finish(1, "split read with an error");
                    checkInd(StatusGeneral_c, '1', "split read with an error");
                    Mem_v.setReadError(0, 1, 0);
                else
                    -- Top of a 40-bit address space
                    Cmd_v       := tbCmd(x"6C", 0, 16, 79);
                    Cmd_v.Ext   := x"FF";
                    Cmd_v.Addr  := x"FFFFFFF0";
                    send(tbCommand(Cmd_v, tbBytes(16, 5)));
                    expect(tbWriteReply(Cmd_v, x"00"), "write at the top of the address space");
                    finish(1, "write at the top of the address space");
                    Cmd_v.Instr := x"4C";
                    send(tbCommand(Cmd_v, tbBytes(0)));
                    expect(tbReadReply(Cmd_v, x"00", 16, tbBytes(16, 5)), "read at the top of the address space");
                    finish(1, "read at the top of the address space");
                end if;

            elsif run("test_windows") then

                -- TC-TG-21: every address window of the configuration bounds the accesses (window w from
                -- 0x1000 (w + 1) to 0x1000 (w + 1) + 0xFF); without windows every access passes
                for w in 0 to WinMax_c - 1 loop
                    Cfg.Win(w) <= tbWin("11000", std_logic_vector(to_unsigned(16#1000# * (w + 1), 40)),
                                        std_logic_vector(to_unsigned(16#1000# * (w + 1) + 16#FF#, 40)));
                end loop;

                wait until rising_edge(Clk);

                for w in 0 to WinMax_c - 1 loop
                    Addr_v := 16#1000# * (w + 1);
                    if w < Windows_g then
                        writeCmd(x"6C", Addr_v, tbBytes(4, w), x"00", "start of window " & to_string(w));
                        writeCmd(x"6C", Addr_v + 16#FC#, tbBytes(4, w), x"00", "end of window " & to_string(w));
                        rejectCmd(tbCmd(x"6C", Addr_v - 1, 2), tbBytes(2), StatusNotAuth_c,
                                  "across the start of window " & to_string(w));
                        rejectCmd(tbCmd(x"4C", Addr_v + 16#FF#, 2), tbBytes(0), StatusNotAuth_c,
                                  "across the end of window " & to_string(w));
                    elsif Windows_g = 0 then
                        writeCmd(x"6C", Addr_v - 1, tbBytes(2, w), x"00", "no windows " & to_string(w));
                    else
                        rejectCmd(tbCmd(x"6C", Addr_v, 4), tbBytes(4), StatusNotAuth_c,
                                  "window " & to_string(w) & " not configured");
                    end if;
                end loop;

            elsif run("test_ecc") then
                -- TC-TG-15: errors in the data buffers
                inject("001", '0');
                writeCmd(x"7C", 16#100#, tbBytes(8), x"00", "single error in the write buffer");
                checkMem(16#100#, tbBytes(8), "corrected data");
                check_value(Obs.SecCnt, 1, error, "single error counted");
                inject("010", '0');
                writeCmd(x"6C", 16#180#, tbBytes(8, 1), x"00", "single error in the write data of the master");
                checkMem(16#180#, tbBytes(8, 1), "corrected write data");
                Mem_v.fill(0, 16#1C0#, 8, 7);
                inject("100", '0');
                readCmd(x"4C", 16#1C0#, 8, tbBytes(8, 7), "single error in the read data of the master");
                check_value(Obs.SecCnt, 3, error, "single errors counted");
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

        omapTestEnd(runner);
    end process;

    i_th : entity work.omap_target_th
        generic map (
            AxiAddrWidth_g => AxiAddrWidth_g,
            AxiDataWidth_g => AxiDataWidth_g,
            BufferBytes_g  => BufferBytes_g,
            Windows_g      => Windows_g,
            ExtAuth_g      => ExtAuth_g,
            ChunkBytes_g   => ChunkBytes_g,
            AxiMaxBeats_g  => AxiMaxBeats_g
        )
        port map (
            Clk => Clk,
            Rst => Rst,
            Cfg => Cfg,
            Obs => Obs
        );

end architecture;
