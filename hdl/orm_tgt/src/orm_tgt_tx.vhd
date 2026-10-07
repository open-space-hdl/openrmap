---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reply encoder of the RMAP target (TG-5): sends the Reply SpaceWire Address formed from the Reply
-- Address field, the reply header with its Header CRC and, for read and read-modify-write replies,
-- the data taken from the data input with its Data CRC, followed by an EOP, or an EEP when the end
-- input requests it.
--
-- Documentation: hdl/orm_tgt/docs/architecture.md

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
entity orm_tgt_tx is
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Reply request
        Rep_Valid     : in    std_logic;
        Rep_Ready     : out   std_logic;
        Rep_Hdr       : in    CmdHeader_t;                   -- Header of the command
        Rep_Status    : in    std_logic_vector(7 downto 0);
        Rep_Read      : in    std_logic;                     -- Read or read-modify-write reply format
        Rep_LenField  : in    std_logic_vector(23 downto 0); -- Data Length field of a read format reply
        Rep_DataCount : in    std_logic_vector(23 downto 0); -- Data bytes taken from the data input
        -- Data of a read format reply
        Data_Valid    : in    std_logic;
        Data_Ready    : out   std_logic;
        Data_Byte     : in    std_logic_vector(7 downto 0);
        -- End of a read format reply after the data: Data CRC and EOP, or EEP
        End_Valid     : in    std_logic;
        End_Ready     : out   std_logic;
        End_Eep       : in    std_logic;
        -- Reply packets (N-Char stream)
        Out_Data      : out   std_logic_vector(7 downto 0);
        Out_Last      : out   std_logic;
        Out_Valid     : out   std_logic;
        Out_Ready     : in    std_logic;
        -- One-cycle event at the end of every reply
        Evt_Sent      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_tgt_tx is

    type Fsm_t is (Idle_s, Path_s, Head_s, HeadCrc_s, Data_s, End_s, DataCrc_s, Mark_s);

    type Head_t is array (0 to 10) of std_logic_vector(7 downto 0);

    type TwoProcess_r is record
        Fsm      : Fsm_t;
        Path     : std_logic_vector(ReplyAddrMax_c * 8 - 1 downto 0); -- First byte in the top byte
        PathCnt  : natural range 0 to ReplyAddrMax_c;
        Head     : Head_t;
        HeadLen  : natural range 7 to 11;
        Idx      : natural range 0 to 11;
        ReadFmt  : std_logic;
        Remain   : unsigned(23 downto 0);
        Crc      : std_logic_vector(7 downto 0);
        Eep      : std_logic;
        OutValid : std_logic;
        OutData  : std_logic_vector(7 downto 0);
        OutLast  : std_logic;
        Sent     : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Free_v : boolean; -- Output register can take a character
        variable Ra_v   : natural range 0 to ReplyAddrMax_c;
        variable Len_v  : std_logic_vector(23 downto 0);
    begin
        v          := r;
        v.Sent     := '0';
        Rep_Ready  <= '0';
        Data_Ready <= '0';
        End_Ready  <= '0';

        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;
        Free_v := r.OutValid = '0' or Out_Ready = '1';

        case r.Fsm is

            when Idle_s =>
                Rep_Ready <= '1';
                if Rep_Valid = '1' then
                    Ra_v := replyAddrBytes(Rep_Hdr.Instr);
                    -- First Reply Address byte to the top byte
                    v.Path    := std_logic_vector(shift_left(unsigned(Rep_Hdr.ReplyAddr), 8 * (ReplyAddrMax_c - Ra_v)));
                    v.PathCnt := Ra_v;
                    v.ReadFmt := Rep_Read;
                    v.Remain  := unsigned(Rep_DataCount);
                    Len_v     := Rep_LenField;
                    -- Reply header (ECSS 5.3.2, 5.4.2, 5.5.2)
                    v.Head(0)  := Rep_Hdr.Ila;
                    v.Head(1)  := ProtocolId_c;
                    v.Head(2)  := "00" & Rep_Hdr.Instr(5 downto 0);
                    v.Head(3)  := Rep_Status;
                    v.Head(4)  := Rep_Hdr.Tla;
                    v.Head(5)  := Rep_Hdr.Tid(15 downto 8);
                    v.Head(6)  := Rep_Hdr.Tid(7 downto 0);
                    v.Head(7)  := x"00";
                    v.Head(8)  := Len_v(23 downto 16);
                    v.Head(9)  := Len_v(15 downto 8);
                    v.Head(10) := Len_v(7 downto 0);
                    if Rep_Read = '1' then
                        v.HeadLen := 11;
                    else
                        v.HeadLen := 7;
                    end if;
                    v.Idx := 0;
                    v.Crc := (others => '0');
                    v.Fsm := Path_s;
                end if;

            when Path_s =>
                -- ECSS 5.1.6c, d: leading 0x00 bytes are not sent, but the last byte of an all-zero field is
                if r.PathCnt = 0 then
                    v.Fsm := Head_s;
                elsif r.PathCnt > 1 and r.Path(ReplyAddrMax_c * 8 - 1 downto ReplyAddrMax_c * 8 - 8) = x"00" and
                      r.Idx = 0 then
                    v.Path    := r.Path(ReplyAddrMax_c * 8 - 9 downto 0) & x"00";
                    v.PathCnt := r.PathCnt - 1;
                elsif Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Path(ReplyAddrMax_c * 8 - 1 downto ReplyAddrMax_c * 8 - 8);
                    v.OutLast  := '0';
                    v.Path     := r.Path(ReplyAddrMax_c * 8 - 9 downto 0) & x"00";
                    v.PathCnt  := r.PathCnt - 1;
                    -- After the first byte sent, zeros are sent
                    v.Idx := 1;
                    if r.PathCnt = 1 then
                        v.Idx := 0;
                        v.Fsm := Head_s;
                    end if;
                end if;

            when Head_s =>
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Head(r.Idx);
                    v.OutLast  := '0';
                    v.Crc      := crcUpdate(r.Crc, r.Head(r.Idx));
                    if r.Idx = r.HeadLen - 1 then
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
                    if r.ReadFmt = '1' then
                        v.Fsm := Data_s;
                    else
                        v.Eep := '0';
                        v.Fsm := Mark_s;
                    end if;
                end if;

            when Data_s =>
                if r.Remain = 0 then
                    v.Fsm := End_s;
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

            when End_s =>
                End_Ready <= '1';
                if End_Valid = '1' then
                    v.Eep := End_Eep;
                    if End_Eep = '1' then
                        -- ECSS 5.4.3.10c.1: memory error, the reply ends with an EEP
                        v.Fsm := Mark_s;
                    else
                        v.Fsm := DataCrc_s;
                    end if;
                end if;

            when DataCrc_s =>
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Crc;
                    v.OutLast  := '0';
                    v.Fsm      := Mark_s;
                end if;

            when Mark_s =>
                if Free_v then
                    v.OutValid := '1';
                    v.OutData  := "0000000" & r.Eep;
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
    Evt_Sent  <= r.Sent;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm      <= Idle_s;
                r.OutValid <= '0';
                r.Sent     <= '0';
            end if;
        end if;
    end process;

end architecture;
