---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of orm_pkg: the RMAP CRC against the table and the test patterns of ECSS Annex A, the
-- command codes of ECSS Table 5-1 and the RMAP model of the testbenches against the same patterns.
--
-- Documentation: hdl/orm_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.orm_pkg.all;
    use work.orm_tb_pkg.all;
    use work.orm_tb_rmap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of orm_pkg_tb is

    -- ECSS Annex A.4: the four commands and replies, in transmission order
    constant WriteCmd_c : t_slv_array(0 to 32)(7 downto 0) := (
        x"FE", x"01", x"6C", x"00", x"67", x"00", x"00", x"00", x"A0", x"00", x"00", x"00", x"00", x"00", x"10",
        x"9F",
        x"01", x"23", x"45", x"67", x"89", x"AB", x"CD", x"EF", x"10", x"11", x"12", x"13", x"14", x"15", x"16",
        x"17",
        x"56");

    constant WriteRep_c : t_slv_array(0 to 7)(7 downto 0) := (
        x"67", x"01", x"2C", x"00", x"FE", x"00", x"00", x"ED");

    constant ReadCmd_c : t_slv_array(0 to 15)(7 downto 0) := (
        x"FE", x"01", x"4C", x"00", x"67", x"00", x"01", x"00", x"A0", x"00", x"00", x"00", x"00", x"00", x"10",
        x"C9");

    constant ReadRep_c : t_slv_array(0 to 28)(7 downto 0) := (
        x"67", x"01", x"0C", x"00", x"FE", x"00", x"01", x"00", x"00", x"00", x"10", x"6D",
        x"01", x"23", x"45", x"67", x"89", x"AB", x"CD", x"EF", x"10", x"11", x"12", x"13", x"14", x"15", x"16",
        x"17",
        x"56");

    constant WritePathCmd_c : t_slv_array(0 to 47)(7 downto 0) := (
        x"11", x"22", x"33", x"44", x"55", x"66", x"77",
        x"FE", x"01", x"6E", x"00", x"00", x"99", x"AA", x"BB", x"CC", x"DD", x"EE", x"00",
        x"67", x"00", x"02", x"00", x"A0", x"00", x"00", x"10", x"00", x"00", x"10",
        x"7F",
        x"A0", x"A1", x"A2", x"A3", x"A4", x"A5", x"A6", x"A7", x"A8", x"A9", x"AA", x"AB", x"AC", x"AD", x"AE",
        x"AF",
        x"B4");

    constant WritePathRep_c : t_slv_array(0 to 14)(7 downto 0) := (
        x"99", x"AA", x"BB", x"CC", x"DD", x"EE", x"00",
        x"67", x"01", x"2E", x"00", x"FE", x"00", x"02", x"1D");

    constant ReadPathCmd_c : t_slv_array(0 to 23)(7 downto 0) := (
        x"11", x"22", x"33", x"44",
        x"FE", x"01", x"4D", x"00", x"99", x"AA", x"BB", x"CC",
        x"67", x"00", x"03", x"00", x"A0", x"00", x"00", x"10", x"00", x"00", x"10",
        x"F7");

    constant ReadPathRep_c : t_slv_array(0 to 32)(7 downto 0) := (
        x"99", x"AA", x"BB", x"CC",
        x"67", x"01", x"0D", x"00", x"FE", x"00", x"03", x"00", x"00", x"00", x"10", x"52",
        x"A0", x"A1", x"A2", x"A3", x"A4", x"A5", x"A6", x"A7", x"A8", x"A9", x"AA", x"AB", x"AC", x"AD", x"AE",
        x"AF",
        x"B4");

    -- CRC of bytes first to last of a pattern with the function of the package
    function crcOf (
        bytes : t_slv_array;
        first : natural;
        last  : natural) return std_logic_vector is
        variable Crc_v : std_logic_vector(7 downto 0) := x"00";
    begin

        for i in first to last loop
            Crc_v := crcUpdate(Crc_v, bytes(i));
        end loop;

        return Crc_v;
    end function;

    procedure checkArray (
        act : t_slv_array;
        exp : t_slv_array;
        msg : string) is
    begin
        check_value(act'length, exp'length, error, msg & ": length");
        if act'length = exp'length then

            for i in 0 to exp'length - 1 loop
                check_value(act(act'low + i), exp(exp'low + i), error, msg & ": byte " & to_string(i));
            end loop;

        end if;
    end procedure;

begin

    test_runner_watchdog(runner, 1 ms);

    p_main : process is
        variable Crc_v : std_logic_vector(7 downto 0);
        variable Cmd_v : TbCmd_t;
        variable Ok_v  : boolean;
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            if run("test_crc_table") then
                -- TC-PKG-01
                Ok_v := true;

                for b in 0 to 255 loop
                    Crc_v := crcUpdate(x"00", std_logic_vector(to_unsigned(b, 8)));
                    if Crc_v /= tbCrc(tbOne(std_logic_vector(to_unsigned(b, 8)))) then
                        Ok_v := false;
                    end if;
                end loop;

                check_value(Ok_v, error, "crcUpdate equals the table of ECSS Annex A.3 for all 256 bytes");
                -- ECSS 5.2e: the CRC over the covered bytes followed by their CRC is zero
                Crc_v := crcOf(WriteCmd_c, 0, 15);
                check_value(Crc_v, x"00", error, "header followed by its CRC gives zero");
                Crc_v := crcOf(WriteCmd_c, 16, 32);
                check_value(Crc_v, x"00", error, "data followed by its CRC gives zero");
                -- ECSS 5.2f: the CRC of no bytes is zero
                check_value(tbCrc(tbBytes(0)), x"00", error, "CRC of an empty field");

            elsif run("test_crc_patterns") then
                -- TC-PKG-02
                check_value(crcOf(WriteCmd_c, 0, 14), x"9F", error, "write command header CRC");
                check_value(crcOf(WriteCmd_c, 16, 31), x"56", error, "write command data CRC");
                check_value(crcOf(WriteRep_c, 0, 6), x"ED", error, "write reply header CRC");
                check_value(crcOf(ReadCmd_c, 0, 14), x"C9", error, "read command header CRC");
                check_value(crcOf(ReadRep_c, 0, 10), x"6D", error, "read reply header CRC");
                check_value(crcOf(ReadRep_c, 12, 27), x"56", error, "read reply data CRC");
                check_value(crcOf(WritePathCmd_c, 7, 29), x"7F", error, "write command with addresses header CRC");
                check_value(crcOf(WritePathCmd_c, 31, 46), x"B4", error, "write command with addresses data CRC");
                check_value(crcOf(WritePathRep_c, 7, 13), x"1D", error, "write reply with address header CRC");
                check_value(crcOf(ReadPathCmd_c, 4, 22), x"F7", error, "read command with addresses header CRC");
                check_value(crcOf(ReadPathRep_c, 4, 14), x"52", error, "read reply with address header CRC");
                check_value(crcOf(ReadPathRep_c, 16, 31), x"B4", error, "read reply with address data CRC");

            elsif run("test_cmd_codes") then
                -- TC-PKG-03: ECSS Table 5-1

                for c in 0 to 15 loop

                    case c is

                        when 2 | 3 =>
                            check_value(cmdKind(std_logic_vector(to_unsigned(c, 4))) = CmdRead, error,
                                        "code " & to_string(c) & " is a read");

                        when 7 =>
                            check_value(cmdKind(std_logic_vector(to_unsigned(c, 4))) = CmdRmw, error,
                                        "code 7 is a read-modify-write");

                        when 8 to 15 =>
                            check_value(cmdKind(std_logic_vector(to_unsigned(c, 4))) = CmdWrite, error,
                                        "code " & to_string(c) & " is a write");

                        when others =>
                            check_value(cmdKind(std_logic_vector(to_unsigned(c, 4))) = CmdInvalid, error,
                                        "code " & to_string(c) & " is invalid");

                    end case;

                end loop;

                check_value(cmdCode(x"7C"), "1111", error, "command field of 0x7C");
                check_value(cmdCode(x"4D"), "0011", error, "command field of 0x4D");
                check_value(replyAddrBytes(x"4C"), 0, error, "RAL 0");
                check_value(replyAddrBytes(x"4D"), 4, error, "RAL 1");
                check_value(replyAddrBytes(x"6E"), 8, error, "RAL 2");
                check_value(replyAddrBytes(x"7F"), 12, error, "RAL 3");

            elsif run("test_model") then
                -- TC-PKG-04: the RMAP model reproduces the patterns of ECSS Annex A.4
                Cmd_v           := tbCmd(x"6C", 0, 16);
                Cmd_v.Addr      := x"A0000000";
                checkArray(tbCommand(Cmd_v, WriteCmd_c(16 to 31)), WriteCmd_c, "write command");
                checkArray(tbWriteReply(Cmd_v, x"00"), WriteRep_c, "write reply");
                Cmd_v           := tbCmd(x"4C", 0, 16, 1);
                Cmd_v.Addr      := x"A0000000";
                checkArray(tbCommand(Cmd_v, tbBytes(0)), ReadCmd_c, "read command");
                checkArray(tbReadReply(Cmd_v, x"00", 16, WriteCmd_c(16 to 31)), ReadRep_c, "read reply");
                Cmd_v           := tbCmd(x"6E", 0, 16, 2);
                Cmd_v.Addr      := x"A0000010";
                Cmd_v.PathLen   := 7;
                Cmd_v.Path      := x"000000000000000000" & x"77665544332211";
                Cmd_v.ReplyAddr := x"00000000" & x"00EEDDCCBBAA9900";
                checkArray(tbCommand(Cmd_v, tbBytes(16, 16#A0#)), WritePathCmd_c, "write command with addresses");
                checkArray(tbWriteReply(Cmd_v, x"00"), WritePathRep_c, "write reply with address");
                Cmd_v           := tbCmd(x"4D", 0, 16, 3);
                Cmd_v.Addr      := x"A0000010";
                Cmd_v.PathLen   := 4;
                Cmd_v.Path      := x"000000000000000000000000" & x"44332211";
                Cmd_v.ReplyAddr := x"0000000000000000" & x"CCBBAA99";
                checkArray(tbCommand(Cmd_v, tbBytes(0)), ReadPathCmd_c, "read command with addresses");
                checkArray(tbReadReply(Cmd_v, x"00", 16, tbBytes(16, 16#A0#)), ReadPathRep_c,
                           "read reply with address");
                -- ECSS Table 5-3: Reply Address field to Reply SpaceWire Address
                Cmd_v           := tbCmd(x"4D");
                Cmd_v.ReplyAddr := x"0000000000000000" & x"00000000";
                checkArray(tbReplyPath(Cmd_v), tbOne(x"00"), "0x00 0x00 0x00 0x00");
                Cmd_v.ReplyAddr := x"0000000000000000" & x"02010000";
                checkArray(tbReplyPath(Cmd_v), tbBytes(2, 1), "0x00 0x00 0x01 0x02");
                Cmd_v.ReplyAddr := x"0000000000000000" & x"02000100";
                checkArray(tbReplyPath(Cmd_v), tbCat(tbOne(x"01"), tbCat(tbOne(x"00"), tbOne(x"02"))),
                           "0x00 0x01 0x00 0x02");
                Cmd_v           := tbCmd(x"4E");
                Cmd_v.ReplyAddr := x"00000000" & x"0504030201000000";
                checkArray(tbReplyPath(Cmd_v), tbBytes(5, 1), "0x00 0x00 0x00 0x01 0x02 0x03 0x04 0x05");
            end if;

        end loop;

        ormTestEnd(runner);
    end process;

end architecture;
