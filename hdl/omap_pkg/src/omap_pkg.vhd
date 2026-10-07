---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Definitions shared by all OpenRMAP modules: RMAP field values, instruction bits, command codes,
-- status codes, the RMAP CRC (ECSS-E-ST-50-52C clause 5.2), the decoded command header and the
-- address window configuration of the Target.
--
-- Documentation: hdl/omap_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package omap_pkg is

    -- Protocol Identifier of RMAP (ECSS 5.1.3b) and default logical address (ECSS 5.1.2 note 2)
    constant ProtocolId_c : std_logic_vector(7 downto 0) := x"01";
    constant DefaultLa_c  : std_logic_vector(7 downto 0) := x"FE";

    -- Instruction field (ECSS 5.1.4): bit positions
    constant InstrReserved_c : natural := 7; -- Reserved bit of the packet type field
    constant InstrCommand_c  : natural := 6; -- '1' command, '0' reply
    constant InstrWrite_c    : natural := 5;
    constant InstrVerify_c   : natural := 4;
    constant InstrReply_c    : natural := 3;
    constant InstrInc_c      : natural := 2;

    -- Command field (bits 5 to 2 of the instruction): write, verify, reply, increment
    subtype CmdCode_t is std_logic_vector(3 downto 0);

    -- Kind of a command code (ECSS Table 5-1)
    type CmdKind_t is (CmdInvalid, CmdWrite, CmdRead, CmdRmw);

    -- Status codes (ECSS Table 5-4)
    constant StatusOk_c            : std_logic_vector(7 downto 0) := x"00";
    constant StatusGeneral_c       : std_logic_vector(7 downto 0) := x"01";
    constant StatusUnused_c        : std_logic_vector(7 downto 0) := x"02";
    constant StatusKey_c           : std_logic_vector(7 downto 0) := x"03";
    constant StatusDataCrc_c       : std_logic_vector(7 downto 0) := x"04";
    constant StatusEarlyEop_c      : std_logic_vector(7 downto 0) := x"05";
    constant StatusTooMuch_c       : std_logic_vector(7 downto 0) := x"06";
    constant StatusEep_c           : std_logic_vector(7 downto 0) := x"07";
    constant StatusVerifyOverrun_c : std_logic_vector(7 downto 0) := x"09";
    constant StatusNotAuth_c       : std_logic_vector(7 downto 0) := x"0A";
    constant StatusRmwLength_c     : std_logic_vector(7 downto 0) := x"0B";
    constant StatusTla_c           : std_logic_vector(7 downto 0) := x"0C";

    -- Sizes of the Reply Address field: 4 bytes per RAL step, at most 12 bytes (ECSS 5.1.6a)
    constant ReplyAddrMax_c : positive := 12;

    -- Decoded command header (fields of ECSS 5.1.2 to 5.1.11 in the order of the packet). ReplyAddr holds the
    -- last byte received in bits 7:0, Addr the Extended Address and the Address.
    type CmdHeader_t is record
        Tla       : std_logic_vector(7 downto 0);
        Instr     : std_logic_vector(7 downto 0);
        Key       : std_logic_vector(7 downto 0);
        ReplyAddr : std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0);
        Ila       : std_logic_vector(7 downto 0);
        Tid       : std_logic_vector(15 downto 0);
        Addr      : std_logic_vector(39 downto 0);
        Len       : std_logic_vector(23 downto 0);
    end record;

    constant CmdHeaderInit_c : CmdHeader_t := (
        Tla       => (others => '0'),
        Instr     => (others => '0'),
        Key       => (others => '0'),
        ReplyAddr => (others => '0'),
        Ila       => (others => '0'),
        Tid       => (others => '0'),
        Addr      => (others => '0'),
        Len       => (others => '0')
    );

    -- Address window of the Target (architecture D8): accesses from Base to Last (inclusive)
    type WinCfg_t is record
        Enable       : std_logic;
        Read         : std_logic; -- Read commands
        Write        : std_logic; -- Write commands
        VerifiedOnly : std_logic; -- Write commands only with the verify bit set
        Rmw          : std_logic; -- Read-modify-write commands
        Single       : std_logic; -- Single-address accesses (increment bit clear)
        Base         : std_logic_vector(39 downto 0);
        Last         : std_logic_vector(39 downto 0);
    end record;

    type WinCfgArray_t is array (natural range <>) of WinCfg_t;

    constant WinMax_c : positive := 8;

    constant WinDisabled_c : WinCfg_t := (
        Enable       => '0',
        Read         => '0',
        Write        => '0',
        VerifiedOnly => '0',
        Rmw          => '0',
        Single       => '0',
        Base         => (others => '0'),
        Last         => (others => '0')
    );

    -- Window over the whole address space with all permissions
    constant WinOpen_c : WinCfg_t := (
        Enable       => '1',
        Read         => '1',
        Write        => '1',
        VerifiedOnly => '0',
        Rmw          => '1',
        Single       => '1',
        Base         => (others => '0'),
        Last         => (others => '1')
    );

    -- Default reset configuration of the windows: window 0 open, the others disabled
    constant WinInitOpen_c : WinCfgArray_t(0 to WinMax_c - 1) := (0 => WinOpen_c, others => WinDisabled_c);

    -- RMAP CRC (ECSS 5.2): CRC after one more byte. The CRC register starts at zero; bytes are taken in
    -- transmission order, each least significant bit first.
    function crcUpdate (
        crc  : std_logic_vector(7 downto 0);
        data : std_logic_vector(7 downto 0)) return std_logic_vector;

    -- Kind of a command code; commands with an invalid code have no kind (ECSS Table 5-1)
    function cmdKind (code : CmdCode_t) return CmdKind_t;

    -- Command code of an instruction
    function cmdCode (instr : std_logic_vector(7 downto 0)) return CmdCode_t;

    -- Number of Reply Address bytes of an instruction (ECSS Table 5-2)
    function replyAddrBytes (instr : std_logic_vector(7 downto 0)) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body omap_pkg is

    function crcUpdate (
        crc  : std_logic_vector(7 downto 0);
        data : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable Crc_v : std_logic_vector(7 downto 0);
    begin
        -- g(x) = x^8 + x^2 + x + 1 with the bits in reflected order: the least significant bit of a byte is
        -- the highest power of x (ECSS 5.2c), so the register shifts right and the feedback is x"E0"
        Crc_v := crc xor data;

        for i in 0 to 7 loop
            if Crc_v(0) = '1' then
                Crc_v := ('0' & Crc_v(7 downto 1)) xor x"E0";
            else
                Crc_v := '0' & Crc_v(7 downto 1);
            end if;
        end loop;

        return Crc_v;
    end function;

    function cmdKind (code : CmdCode_t) return CmdKind_t is
    begin
        if code(3) = '1' then
            -- Write: every combination of verify, reply and increment
            return CmdWrite;
        elsif code = "0010" or code = "0011" then
            return CmdRead;
        elsif code = "0111" then
            return CmdRmw;
        else
            return CmdInvalid;
        end if;
    end function;

    function cmdCode (instr : std_logic_vector(7 downto 0)) return CmdCode_t is
    begin
        return instr(InstrWrite_c downto InstrInc_c);
    end function;

    function replyAddrBytes (instr : std_logic_vector(7 downto 0)) return natural is
    begin
        return 4 * to_integer(unsigned(instr(1 downto 0)));
    end function;

end package body;
