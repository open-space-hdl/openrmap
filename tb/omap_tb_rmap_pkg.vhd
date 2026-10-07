---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- RMAP model of the testbenches: builds commands and expected replies byte by byte with its own
-- implementation of ECSS-E-ST-50-52C clauses 5.1 to 5.5. The CRC uses the look-up table of ECSS
-- Annex A.3, independent of the bitwise CRC function of the RTL. Faults (CRC errors, truncation,
-- excess data, EEP) are applied to the byte arrays by the tests.
--
-- Packets are byte arrays without the end of packet marker; omap_tb_pkg.omapPacket appends it for the
-- AXI4-Stream VVCs.
--
-- Documentation: hdl/omap_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package omap_tb_rmap_pkg is

    subtype TbByte_t is std_logic_vector(7 downto 0);

    -- Fields of a command. Path and ReplyAddr hold the bytes in transmission order: byte i in bits
    -- 8 * i + 7 downto 8 * i. ReplyAddr is the Reply Address field as sent (including leading 0x00
    -- bytes), its length is 4 * Instr(1 downto 0).
    type TbCmd_t is record
        PathLen   : natural range 0 to 16;
        Path      : std_logic_vector(16 * 8 - 1 downto 0);
        Tla       : TbByte_t;
        Pid       : TbByte_t;
        Instr     : TbByte_t;
        Key       : TbByte_t;
        ReplyAddr : std_logic_vector(12 * 8 - 1 downto 0);
        Ila       : TbByte_t;
        Tid       : std_logic_vector(15 downto 0);
        Ext       : TbByte_t;
        Addr      : std_logic_vector(31 downto 0);
        Len       : std_logic_vector(23 downto 0);
    end record;

    -- Instructions of the commands (ECSS Table 5-1) with a Reply Address Length of zero
    constant InstrWrite_c      : TbByte_t := x"60"; -- Write, single address, no verify, no reply
    constant InstrWriteInc_c   : TbByte_t := x"64"; -- Write, incrementing, no verify, no reply
    constant InstrWriteReply_c : TbByte_t := x"6C"; -- Write, incrementing, no verify, reply
    constant InstrWriteVer_c   : TbByte_t := x"7C"; -- Write, incrementing, verify, reply
    constant InstrRead_c       : TbByte_t := x"4C"; -- Read, incrementing
    constant InstrReadSingle_c : TbByte_t := x"48"; -- Read, single address
    constant InstrRmw_c        : TbByte_t := x"5C"; -- Read-modify-write

    -- Command with default fields: TLA 0xFE, ILA 0x67, key 0, TID 0, address 0, length 0
    function tbCmd (
        instr : TbByte_t;
        addr  : natural := 0;
        len   : natural := 0;
        tid   : natural := 0) return TbCmd_t;

    -- RMAP CRC of a byte array (ECSS Annex A.3 table method)
    function tbCrc (bytes : t_slv_array) return TbByte_t;

    -- Concatenation of two byte arrays
    function tbCat (
        a : t_slv_array;
        b : t_slv_array) return t_slv_array;

    -- First n bytes of a byte array
    function tbHead (
        a : t_slv_array;
        n : natural) return t_slv_array;

    -- One byte as a byte array
    function tbOne (b : TbByte_t) return t_slv_array;

    -- n bytes with the values (first + i) mod 256
    function tbBytes (
        n     : natural;
        first : natural := 0) return t_slv_array;

    -- Header of a command from the Target Logical Address to the Header CRC (no Target SpaceWire Address)
    function tbCmdHeader (cmd : TbCmd_t) return t_slv_array;

    -- Complete command: Target SpaceWire Address, header with Header CRC and, for write and read-modify-write
    -- commands or with forceData, the data field and the Data CRC. hdrCrcErr and dataCrcErr invert bit 0 of
    -- the respective CRC.
    function tbCommand (
        cmd        : TbCmd_t;
        data       : t_slv_array;
        hdrCrcErr  : boolean := false;
        dataCrcErr : boolean := false;
        forceData  : boolean := false) return t_slv_array;

    -- Reply SpaceWire Address of a command (ECSS 5.1.6c to e)
    function tbReplyPath (cmd : TbCmd_t) return t_slv_array;

    -- Expected write reply to a command (ECSS 5.3.2)
    function tbWriteReply (
        cmd    : TbCmd_t;
        status : TbByte_t) return t_slv_array;

    -- Expected read or read-modify-write reply (ECSS 5.4.2, 5.5.2): lenField is the Data Length field, data
    -- the data field; the Data CRC follows the data unless noCrc is set (reply ended by an EEP)
    function tbReadReply (
        cmd      : TbCmd_t;
        status   : TbByte_t;
        lenField : natural;
        data     : t_slv_array;
        noCrc    : boolean := false) return t_slv_array;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body omap_tb_rmap_pkg is

    type CrcTable_t is array (0 to 255) of natural range 0 to 255;

    -- ECSS Annex A.3
    constant CrcTable_c : CrcTable_t := (
        16#00#, 16#91#, 16#e3#, 16#72#, 16#07#, 16#96#, 16#e4#, 16#75#,
        16#0e#, 16#9f#, 16#ed#, 16#7c#, 16#09#, 16#98#, 16#ea#, 16#7b#,
        16#1c#, 16#8d#, 16#ff#, 16#6e#, 16#1b#, 16#8a#, 16#f8#, 16#69#,
        16#12#, 16#83#, 16#f1#, 16#60#, 16#15#, 16#84#, 16#f6#, 16#67#,
        16#38#, 16#a9#, 16#db#, 16#4a#, 16#3f#, 16#ae#, 16#dc#, 16#4d#,
        16#36#, 16#a7#, 16#d5#, 16#44#, 16#31#, 16#a0#, 16#d2#, 16#43#,
        16#24#, 16#b5#, 16#c7#, 16#56#, 16#23#, 16#b2#, 16#c0#, 16#51#,
        16#2a#, 16#bb#, 16#c9#, 16#58#, 16#2d#, 16#bc#, 16#ce#, 16#5f#,
        16#70#, 16#e1#, 16#93#, 16#02#, 16#77#, 16#e6#, 16#94#, 16#05#,
        16#7e#, 16#ef#, 16#9d#, 16#0c#, 16#79#, 16#e8#, 16#9a#, 16#0b#,
        16#6c#, 16#fd#, 16#8f#, 16#1e#, 16#6b#, 16#fa#, 16#88#, 16#19#,
        16#62#, 16#f3#, 16#81#, 16#10#, 16#65#, 16#f4#, 16#86#, 16#17#,
        16#48#, 16#d9#, 16#ab#, 16#3a#, 16#4f#, 16#de#, 16#ac#, 16#3d#,
        16#46#, 16#d7#, 16#a5#, 16#34#, 16#41#, 16#d0#, 16#a2#, 16#33#,
        16#54#, 16#c5#, 16#b7#, 16#26#, 16#53#, 16#c2#, 16#b0#, 16#21#,
        16#5a#, 16#cb#, 16#b9#, 16#28#, 16#5d#, 16#cc#, 16#be#, 16#2f#,
        16#e0#, 16#71#, 16#03#, 16#92#, 16#e7#, 16#76#, 16#04#, 16#95#,
        16#ee#, 16#7f#, 16#0d#, 16#9c#, 16#e9#, 16#78#, 16#0a#, 16#9b#,
        16#fc#, 16#6d#, 16#1f#, 16#8e#, 16#fb#, 16#6a#, 16#18#, 16#89#,
        16#f2#, 16#63#, 16#11#, 16#80#, 16#f5#, 16#64#, 16#16#, 16#87#,
        16#d8#, 16#49#, 16#3b#, 16#aa#, 16#df#, 16#4e#, 16#3c#, 16#ad#,
        16#d6#, 16#47#, 16#35#, 16#a4#, 16#d1#, 16#40#, 16#32#, 16#a3#,
        16#c4#, 16#55#, 16#27#, 16#b6#, 16#c3#, 16#52#, 16#20#, 16#b1#,
        16#ca#, 16#5b#, 16#29#, 16#b8#, 16#cd#, 16#5c#, 16#2e#, 16#bf#,
        16#90#, 16#01#, 16#73#, 16#e2#, 16#97#, 16#06#, 16#74#, 16#e5#,
        16#9e#, 16#0f#, 16#7d#, 16#ec#, 16#99#, 16#08#, 16#7a#, 16#eb#,
        16#8c#, 16#1d#, 16#6f#, 16#fe#, 16#8b#, 16#1a#, 16#68#, 16#f9#,
        16#82#, 16#13#, 16#61#, 16#f0#, 16#85#, 16#14#, 16#66#, 16#f7#,
        16#a8#, 16#39#, 16#4b#, 16#da#, 16#af#, 16#3e#, 16#4c#, 16#dd#,
        16#a6#, 16#37#, 16#45#, 16#d4#, 16#a1#, 16#30#, 16#42#, 16#d3#,
        16#b4#, 16#25#, 16#57#, 16#c6#, 16#b3#, 16#22#, 16#50#, 16#c1#,
        16#ba#, 16#2b#, 16#59#, 16#c8#, 16#bd#, 16#2c#, 16#5e#, 16#cf#
    );

    function tbCmd (
        instr : TbByte_t;
        addr  : natural := 0;
        len   : natural := 0;
        tid   : natural := 0) return TbCmd_t is
        variable Cmd_v : TbCmd_t;
    begin
        Cmd_v.PathLen   := 0;
        Cmd_v.Path      := (others => '0');
        Cmd_v.Tla       := x"FE";
        Cmd_v.Pid       := x"01";
        Cmd_v.Instr     := instr;
        Cmd_v.Key       := x"00";
        Cmd_v.ReplyAddr := (others => '0');
        Cmd_v.Ila       := x"67";
        Cmd_v.Tid       := std_logic_vector(to_unsigned(tid, 16));
        Cmd_v.Ext       := x"00";
        Cmd_v.Addr      := std_logic_vector(to_unsigned(addr, 32));
        Cmd_v.Len       := std_logic_vector(to_unsigned(len, 24));
        return Cmd_v;
    end function;

    function tbCrc (bytes : t_slv_array) return TbByte_t is
        variable Crc_v : natural range 0 to 255 := 0;
    begin

        for i in bytes'range loop
            Crc_v := CrcTable_c(to_integer(to_unsigned(Crc_v, 8) xor unsigned(bytes(i))));
        end loop;

        return std_logic_vector(to_unsigned(Crc_v, 8));
    end function;

    function tbCat (
        a : t_slv_array;
        b : t_slv_array) return t_slv_array is
        variable Res_v : t_slv_array(0 to a'length + b'length - 1)(7 downto 0);
    begin

        for i in 0 to a'length - 1 loop
            Res_v(i) := a(a'low + i);
        end loop;

        for i in 0 to b'length - 1 loop
            Res_v(a'length + i) := b(b'low + i);
        end loop;

        return Res_v;
    end function;

    function tbHead (
        a : t_slv_array;
        n : natural) return t_slv_array is
        variable Res_v : t_slv_array(0 to n - 1)(7 downto 0);
    begin

        for i in 0 to n - 1 loop
            Res_v(i) := a(a'low + i);
        end loop;

        return Res_v;
    end function;

    function tbOne (b : TbByte_t) return t_slv_array is
        variable Res_v : t_slv_array(0 to 0)(7 downto 0);
    begin
        Res_v(0) := b;
        return Res_v;
    end function;

    function tbBytes (
        n     : natural;
        first : natural := 0) return t_slv_array is
        variable Res_v : t_slv_array(0 to n - 1)(7 downto 0);
    begin

        for i in 0 to n - 1 loop
            Res_v(i) := std_logic_vector(to_unsigned((first + i) mod 256, 8));
        end loop;

        return Res_v;
    end function;

    function tbCmdHeader (cmd : TbCmd_t) return t_slv_array is
        constant RaBytes_c : natural := 4 * to_integer(unsigned(cmd.Instr(1 downto 0)));
        variable Hdr_v     : t_slv_array(0 to 14 + RaBytes_c)(7 downto 0);
        variable Idx_v     : natural := 0;

        procedure put (b : TbByte_t) is
        begin
            Hdr_v(Idx_v) := b;
            Idx_v        := Idx_v + 1;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        put(cmd.Tla);
        put(cmd.Pid);
        put(cmd.Instr);
        put(cmd.Key);

        for i in 0 to RaBytes_c - 1 loop
            put(cmd.ReplyAddr(8 * i + 7 downto 8 * i));
        end loop;

        put(cmd.Ila);
        put(cmd.Tid(15 downto 8));
        put(cmd.Tid(7 downto 0));
        put(cmd.Ext);
        put(cmd.Addr(31 downto 24));
        put(cmd.Addr(23 downto 16));
        put(cmd.Addr(15 downto 8));
        put(cmd.Addr(7 downto 0));
        put(cmd.Len(23 downto 16));
        put(cmd.Len(15 downto 8));
        put(cmd.Len(7 downto 0));
        return Hdr_v;
    end function;

    function tbCommand (
        cmd        : TbCmd_t;
        data       : t_slv_array;
        hdrCrcErr  : boolean := false;
        dataCrcErr : boolean := false;
        forceData  : boolean := false) return t_slv_array is
        constant Hdr_c   : t_slv_array := tbCmdHeader(cmd);
        variable Path_v  : t_slv_array(0 to cmd.PathLen - 1)(7 downto 0);
        variable Crc_v   : TbByte_t;
        variable WithD_v : boolean;
    begin

        for i in 0 to cmd.PathLen - 1 loop
            Path_v(i) := cmd.Path(8 * i + 7 downto 8 * i);
        end loop;

        Crc_v := tbCrc(Hdr_c);
        if hdrCrcErr then
            Crc_v(0) := not Crc_v(0);
        end if;
        -- Write commands and read-modify-write commands carry a data field (ECSS 5.3.1, 5.5.1)
        WithD_v := cmd.Instr(5) = '1' or cmd.Instr(5 downto 2) = "0111" or forceData;
        if not WithD_v then
            return tbCat(tbCat(Path_v, Hdr_c), tbOne(Crc_v));
        end if;
        if dataCrcErr then
            return tbCat(tbCat(tbCat(tbCat(Path_v, Hdr_c), tbOne(Crc_v)), data), tbOne(tbCrc(data) xor x"01"));
        end if;
        return tbCat(tbCat(tbCat(tbCat(Path_v, Hdr_c), tbOne(Crc_v)), data), tbOne(tbCrc(data)));
    end function;

    function tbReplyPath (cmd : TbCmd_t) return t_slv_array is
        constant RaBytes_c : natural := 4 * to_integer(unsigned(cmd.Instr(1 downto 0)));
        variable First_v   : natural := RaBytes_c;
        variable Res_v     : t_slv_array(0 to RaBytes_c - 1)(7 downto 0);
        variable Cnt_v     : natural := 0;
    begin
        -- Leading 0x00 bytes are ignored (ECSS 5.1.6c); an all-zero field gives a single 0x00 (5.1.6d)

        for i in RaBytes_c - 1 downto 0 loop
            if cmd.ReplyAddr(8 * i + 7 downto 8 * i) /= x"00" then
                First_v := i;
            end if;
        end loop;

        if RaBytes_c > 0 and First_v = RaBytes_c then
            return tbOne(x"00");
        end if;

        for i in First_v to RaBytes_c - 1 loop
            Res_v(Cnt_v) := cmd.ReplyAddr(8 * i + 7 downto 8 * i);
            Cnt_v        := Cnt_v + 1;
        end loop;

        return tbHead(Res_v, Cnt_v);
    end function;

    function tbWriteReply (
        cmd    : TbCmd_t;
        status : TbByte_t) return t_slv_array is
        variable Hdr_v : t_slv_array(0 to 6)(7 downto 0);
    begin
        Hdr_v(0) := cmd.Ila;
        Hdr_v(1) := x"01";
        Hdr_v(2) := "00" & cmd.Instr(5 downto 0);
        Hdr_v(3) := status;
        Hdr_v(4) := cmd.Tla;
        Hdr_v(5) := cmd.Tid(15 downto 8);
        Hdr_v(6) := cmd.Tid(7 downto 0);
        return tbCat(tbCat(tbReplyPath(cmd), Hdr_v), tbOne(tbCrc(Hdr_v)));
    end function;

    function tbReadReply (
        cmd      : TbCmd_t;
        status   : TbByte_t;
        lenField : natural;
        data     : t_slv_array;
        noCrc    : boolean := false) return t_slv_array is
        variable Hdr_v : t_slv_array(0 to 10)(7 downto 0);
        variable Len_v : std_logic_vector(23 downto 0);
    begin
        Len_v     := std_logic_vector(to_unsigned(lenField, 24));
        Hdr_v(0)  := cmd.Ila;
        Hdr_v(1)  := x"01";
        Hdr_v(2)  := "00" & cmd.Instr(5 downto 0);
        Hdr_v(3)  := status;
        Hdr_v(4)  := cmd.Tla;
        Hdr_v(5)  := cmd.Tid(15 downto 8);
        Hdr_v(6)  := cmd.Tid(7 downto 0);
        Hdr_v(7)  := x"00";
        Hdr_v(8)  := Len_v(23 downto 16);
        Hdr_v(9)  := Len_v(15 downto 8);
        Hdr_v(10) := Len_v(7 downto 0);
        if noCrc then
            return tbCat(tbCat(tbCat(tbReplyPath(cmd), Hdr_v), tbOne(tbCrc(Hdr_v))), data);
        end if;
        return tbCat(tbCat(tbCat(tbCat(tbReplyPath(cmd), Hdr_v), tbOne(tbCrc(Hdr_v))), data), tbOne(tbCrc(data)));
    end function;

end package body;
