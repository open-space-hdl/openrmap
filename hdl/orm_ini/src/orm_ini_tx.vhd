---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Command encoder of the RMAP initiator (IN-1): builds a write, read or read-modify-write command from
-- a request descriptor and the data stream: Target SpaceWire Address, header with the Reply Address
-- padded with leading 0x00 bytes to the smallest number of words, Header CRC, data (write and
-- read-modify-write), Data CRC and EOP. A request whose reply cannot be registered in the transaction
-- table (Transaction Identifier in use) is not sent; its data is consumed and it is confirmed with a
-- local error.
--
-- Documentation: hdl/orm_ini/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.orm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_ini_tx is
    generic (
        TgtAddrBytes_g : natural range 0 to 16 := 8
    );
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Request (ECSS 5.3.3.2b, 5.4.3.2b, 5.5.3.2b)
        Req_Valid        : in    std_logic;
        Req_Ready        : out   std_logic;
        Req_Code         : in    std_logic_vector(3 downto 0); -- Write, verify, reply, increment
        Req_TgtAddr      : in    std_logic_vector(maximum(TgtAddrBytes_g, 1) * 8 - 1 downto 0); -- Byte i in bits 8i+7:8i
        Req_TgtAddrLen   : in    std_logic_vector(4 downto 0);
        Req_Tla          : in    std_logic_vector(7 downto 0);
        Req_Key          : in    std_logic_vector(7 downto 0);
        Req_ReplyAddr    : in    std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0);         -- Byte i in bits 8i+7:8i
        Req_ReplyAddrLen : in    std_logic_vector(3 downto 0);
        Req_Ila          : in    std_logic_vector(7 downto 0);
        Req_Tid          : in    std_logic_vector(15 downto 0);
        Req_Addr         : in    std_logic_vector(39 downto 0);
        Req_Len          : in    std_logic_vector(23 downto 0);
        -- Data of write and read-modify-write commands (Data Length bytes)
        Data_Valid       : in    std_logic;
        Data_Ready       : out   std_logic;
        Data_Byte        : in    std_logic_vector(7 downto 0);
        -- Transaction table: registration of a command with reply
        Reg_Valid        : out   std_logic;
        Reg_Instr        : out   std_logic_vector(7 downto 0);
        Reg_Tid          : out   std_logic_vector(15 downto 0);
        Reg_Ready        : in    std_logic;                    -- Table can register (a free entry)
        Reg_Busy         : in    std_logic;                    -- Transaction Identifier already registered
        -- Local rejection (Transaction Identifier in use)
        Rej_Valid        : out   std_logic;
        Rej_Ready        : in    std_logic;
        Rej_Tid          : out   std_logic_vector(15 downto 0);
        Rej_Instr        : out   std_logic_vector(7 downto 0);
        -- Command packets (N-Char stream)
        Out_Data         : out   std_logic_vector(7 downto 0);
        Out_Last         : out   std_logic;
        Out_Valid        : out   std_logic;
        Out_Ready        : in    std_logic;
        -- One-cycle event per command sent
        Evt_Sent         : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_ini_tx is

    constant PathBits_c : positive := maximum(TgtAddrBytes_g, 1) * 8;

    type Fsm_t is (Idle_s, Check_s, Reject_s, Drop_s, Path_s, Head_s, HeadCrc_s, Data_s, DataCrc_s, Eop_s);

    type TwoProcess_r is record
        Fsm      : Fsm_t;
        Path     : std_logic_vector(PathBits_c - 1 downto 0);
        PathCnt  : natural range 0 to 16;
        Instr    : std_logic_vector(7 downto 0);
        Tla      : std_logic_vector(7 downto 0);
        Key      : std_logic_vector(7 downto 0);
        Ra       : std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0); -- Padded field, first byte in bits 7:0
        Ila      : std_logic_vector(7 downto 0);
        Tid      : std_logic_vector(15 downto 0);
        Addr     : std_logic_vector(39 downto 0);
        Len      : std_logic_vector(23 downto 0);
        HasData  : std_logic;
        Reply    : std_logic;
        Idx      : natural range 0 to 31;
        Remain   : unsigned(23 downto 0);
        Crc      : std_logic_vector(7 downto 0);
        OutValid : std_logic;
        OutData  : std_logic_vector(7 downto 0);
        OutLast  : std_logic;
        RegValid : std_logic;
        Sent     : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Free_v  : boolean;
        variable Ral_v   : natural range 0 to 3;
        variable RaLen_v : natural range 0 to 15;
        variable Rel_v   : integer range -16 to 31;
        variable Byte_v  : std_logic_vector(7 downto 0);
        variable Kind_v  : CmdKind_t;
    begin
        v          := r;
        v.RegValid := '0';
        v.Sent     := '0';
        Req_Ready  <= '0';
        Data_Ready <= '0';
        Rej_Valid  <= '0';

        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;
        Free_v := r.OutValid = '0' or Out_Ready = '1';

        case r.Fsm is

            when Idle_s =>
                Req_Ready <= '1';
                if Req_Valid = '1' then
                    -- ECSS 5.3.1.5.4: Reply Address Length, the smallest number of words for the Reply Address
                    RaLen_v := minimum(to_integer(unsigned(Req_ReplyAddrLen)), ReplyAddrMax_c);
                    Ral_v   := (RaLen_v + 3) / 4;
                    -- Field padded with leading zeros: the address bytes at the end of the field
                    v.Ra      := std_logic_vector(shift_left(unsigned(Req_ReplyAddr), 8 * (4 * Ral_v - RaLen_v)));
                    v.Path    := Req_TgtAddr;
                    v.PathCnt := minimum(to_integer(unsigned(Req_TgtAddrLen)), TgtAddrBytes_g);
                    v.Instr   := "01" & Req_Code & std_logic_vector(to_unsigned(Ral_v, 2));
                    v.Tla     := Req_Tla;
                    v.Key     := Req_Key;
                    v.Ila     := Req_Ila;
                    v.Tid     := Req_Tid;
                    v.Addr    := Req_Addr;
                    v.Len     := Req_Len;
                    v.Reply   := Req_Code(InstrReply_c - 2);
                    Kind_v    := cmdKind(Req_Code);
                    if Kind_v = CmdWrite or Kind_v = CmdRmw then
                        v.HasData := '1';
                    else
                        v.HasData := '0';
                    end if;
                    v.Remain := unsigned(Req_Len);
                    v.Fsm    := Check_s;
                end if;

            when Check_s =>
                -- Commands with reply are registered in the transaction table
                if r.Reply = '0' then
                    v.Fsm := Path_s;
                elsif Reg_Busy = '1' then
                    v.Fsm := Reject_s;
                elsif Reg_Ready = '1' then
                    v.RegValid := '1';
                    v.Fsm      := Path_s;
                end if;
                v.Idx := 0;
                v.Crc := (others => '0');

            when Reject_s =>
                Rej_Valid <= '1';
                if Rej_Ready = '1' then
                    v.Fsm := Drop_s;
                end if;

            when Drop_s =>
                -- Data of a rejected request is consumed
                if r.HasData = '1' and r.Remain /= 0 then
                    Data_Ready <= '1';
                    if Data_Valid = '1' then
                        v.Remain := r.Remain - 1;
                    end if;
                else
                    v.Fsm := Idle_s;
                end if;

            when Path_s =>
                -- ECSS 5.1.1: Target SpaceWire Address
                if r.PathCnt = 0 then
                    v.Fsm := Head_s;
                elsif Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Path(7 downto 0);
                    v.OutLast  := '0';
                    v.Path     := std_logic_vector(shift_right(unsigned(r.Path), 8));
                    v.PathCnt  := r.PathCnt - 1;
                end if;

            when Head_s =>
                -- Header from the Target Logical Address to the Data Length (ECSS 5.3.1, 5.4.1, 5.5.1)
                Ral_v := to_integer(unsigned(r.Instr(1 downto 0)));
                Rel_v := r.Idx - 4 - 4 * Ral_v;
                if r.Idx = 0 then
                    Byte_v := r.Tla;
                elsif r.Idx = 1 then
                    Byte_v := ProtocolId_c;
                elsif r.Idx = 2 then
                    Byte_v := r.Instr;
                elsif r.Idx = 3 then
                    Byte_v := r.Key;
                elsif Rel_v < 0 then
                    Byte_v := r.Ra(8 * (r.Idx - 4) + 7 downto 8 * (r.Idx - 4));
                else

                    case Rel_v is
                        when 0 => Byte_v := r.Ila;
                        when 1 => Byte_v := r.Tid(15 downto 8);
                        when 2 => Byte_v := r.Tid(7 downto 0);
                        when 3 => Byte_v := r.Addr(39 downto 32);
                        when 4 => Byte_v := r.Addr(31 downto 24);
                        when 5 => Byte_v := r.Addr(23 downto 16);
                        when 6 => Byte_v := r.Addr(15 downto 8);
                        when 7 => Byte_v := r.Addr(7 downto 0);
                        when 8 => Byte_v := r.Len(23 downto 16);
                        when 9 => Byte_v := r.Len(15 downto 8);
                        when others => Byte_v := r.Len(7 downto 0);
                    end case;

                end if;
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := Byte_v;
                    v.OutLast  := '0';
                    v.Crc      := crcUpdate(r.Crc, Byte_v);
                    if Rel_v = 10 then
                        v.Fsm := HeadCrc_s;
                    else
                        v.Idx := r.Idx + 1;
                    end if;
                end if;

            when HeadCrc_s =>
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Crc;
                    v.OutLast  := '0';
                    v.Crc      := (others => '0');
                    if r.HasData = '1' then
                        v.Fsm := Data_s;
                    else
                        v.Fsm := Eop_s;
                    end if;
                end if;

            when Data_s =>
                if r.Remain = 0 then
                    v.Fsm := DataCrc_s;
                elsif Free_v then
                    Data_Ready <= '1';
                    if Data_Valid = '1' then
                        v.OutValid := '1';
                        v.OutData  := Data_Byte;
                        v.OutLast  := '0';
                        v.Crc      := crcUpdate(r.Crc, Data_Byte);
                        v.Remain   := r.Remain - 1;
                    end if;
                end if;

            when DataCrc_s =>
                -- ECSS 5.2f: the Data CRC of an empty data field is 0x00
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Crc;
                    v.OutLast  := '0';
                    v.Fsm      := Eop_s;
                end if;

            when Eop_s =>
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := x"00";
                    v.OutLast  := '1';
                    v.Sent     := '1';
                    v.Fsm      := Idle_s;
                end if;

            -- Recovery state for an illegal state
            -- coverage off
            when others =>
                v.Fsm := Idle_s;
            -- coverage on

        end case;

        r_next <= v;
    end process;

    Out_Data  <= r.OutData;
    Out_Last  <= r.OutLast;
    Out_Valid <= r.OutValid;
    Reg_Valid <= r.RegValid;
    Reg_Instr <= r.Instr;
    Reg_Tid   <= r.Tid;
    Rej_Tid   <= r.Tid;
    Rej_Instr <= r.Instr;
    Evt_Sent  <= r.Sent;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm      <= Idle_s;
                r.OutValid <= '0';
                r.RegValid <= '0';
                r.Sent     <= '0';
            end if;
        end if;
    end process;

end architecture;
