---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reply decoder of the RMAP initiator (IN-2): decodes write replies and read and read-modify-write
-- replies, checks the Header CRC, the packet type and the reply bit, associates the reply with an
-- outstanding command through the transaction table, passes the data of read format replies on as
-- they arrive (two bytes delayed, so that the last data byte carries TLast also when the reply is
-- too short) and checks the data length and the Data CRC. Every reply with an intact header ends
-- with a confirmation; a reply with a corrupted data field is confirmed with a local error.
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
entity orm_ini_rx is
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Reply packets (N-Char stream)
        In_Data        : in    std_logic_vector(7 downto 0);
        In_Last        : in    std_logic;
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        -- Transaction table
        Lk_Tid         : out   std_logic_vector(15 downto 0);
        Lk_Hit         : in    std_logic;
        Lk_Instr       : in    std_logic_vector(7 downto 0);
        Rm_Valid       : out   std_logic;
        Rm_Tid         : out   std_logic_vector(15 downto 0);
        -- Confirmation
        Conf_Valid     : out   std_logic;
        Conf_Ready     : in    std_logic;
        Conf_Tid       : out   std_logic_vector(15 downto 0);
        Conf_Status    : out   std_logic_vector(7 downto 0);
        Conf_Instr     : out   std_logic_vector(7 downto 0);
        Conf_Len       : out   std_logic_vector(23 downto 0);
        Conf_DataErr   : out   std_logic;
        -- Data of read and read-modify-write replies
        Out_Data       : out   std_logic_vector(7 downto 0);
        Out_Last       : out   std_logic;
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic;
        -- Events (one cycle)
        Evt_HdrErr     : out   std_logic; -- Header CRC error, incomplete header, packet type or reply bit wrong
        Evt_Unexpected : out   std_logic; -- No outstanding command with this Transaction Identifier and instruction
        Evt_DataErr    : out   std_logic; -- Reply with a corrupted data field
        Evt_Rx         : out   std_logic  -- Reply confirmed without error
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_ini_rx is

    type Fsm_t is (Hdr_s, Lookup_s, Data_s, Flush_s, Conf_s, Drop_s);

    type Hold_t is array (0 to 1) of std_logic_vector(7 downto 0);

    type TwoProcess_r is record
        Fsm      : Fsm_t;
        Idx      : natural range 0 to 15;
        ReadFmt  : std_logic;
        Crc      : std_logic_vector(7 downto 0);
        Ila      : std_logic_vector(7 downto 0);
        Instr    : std_logic_vector(7 downto 0);
        Status   : std_logic_vector(7 downto 0);
        Tid      : std_logic_vector(15 downto 0);
        Len      : std_logic_vector(23 downto 0);
        Cnt      : unsigned(24 downto 0);
        Hold     : Hold_t;
        HoldCnt  : natural range 0 to 2;
        Eep      : std_logic;
        Excess   : std_logic;
        CrcOk    : std_logic;
        Short    : std_logic;
        DataErr  : std_logic;
        OutValid : std_logic;
        OutData  : std_logic_vector(7 downto 0);
        OutLast  : std_logic;
        EvtHdr   : std_logic;
        EvtUnexp : std_logic;
        EvtData  : std_logic;
        EvtRx    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Free_v : boolean;
        variable Acc_v  : boolean;
        variable Kind_v : CmdKind_t;
        variable Len_v  : unsigned(24 downto 0);
    begin
        v          := r;
        v.EvtHdr   := '0';
        v.EvtUnexp := '0';
        v.EvtData  := '0';
        v.EvtRx    := '0';

        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;
        Free_v := r.OutValid = '0' or Out_Ready = '1';

        -- Characters are taken in the header, while dropping and in the data field when the output can take a byte
        Acc_v := In_Valid = '1' and (r.Fsm = Hdr_s or r.Fsm = Drop_s or (r.Fsm = Data_s and Free_v));
        Len_v := unsigned('0' & r.Len);

        case r.Fsm is

            when Hdr_s =>
                if Acc_v then
                    if In_Last = '1' then
                        -- ECSS 5.3.3.11, 5.4.3.11: incomplete header
                        v.EvtHdr := '1';
                        v.Idx    := 0;
                        v.Crc    := (others => '0');
                    else
                        v.Idx := r.Idx + 1;
                        v.Crc := crcUpdate(r.Crc, In_Data);

                        case r.Idx is

                            when 0 =>
                                v.Ila := In_Data;
                                v.Len := (others => '0');

                            when 1 =>
                                null;

                            when 2 =>
                                v.Instr := In_Data;
                                Kind_v  := cmdKind(cmdCode(In_Data));
                                if Kind_v = CmdRead or Kind_v = CmdRmw then
                                    v.ReadFmt := '1';
                                else
                                    v.ReadFmt := '0';
                                end if;
                                -- ECSS 5.3.3.12, 5.4.3.13: reserved bit set or not a reply, or no reply requested
                                if In_Data(InstrReserved_c) = '1' or In_Data(InstrCommand_c) = '1' or
                                   In_Data(InstrReply_c) = '0' then
                                    v.EvtHdr := '1';
                                    v.Fsm    := Drop_s;
                                end if;

                            when 3 =>
                                v.Status := In_Data;

                            when 4 =>
                                null;

                            when 5 =>
                                v.Tid(15 downto 8) := In_Data;

                            when 6 =>
                                v.Tid(7 downto 0) := In_Data;

                            when 8 =>
                                v.Len(23 downto 16) := In_Data;

                            when 9 =>
                                v.Len(15 downto 8) := In_Data;

                            when 10 =>
                                v.Len(7 downto 0) := In_Data;

                            when others =>
                                null;

                        end case;

                        -- Header CRC after 7 (write reply) or 11 (read format reply) bytes
                        if (r.ReadFmt = '0' and r.Idx = 7) or (r.ReadFmt = '1' and r.Idx = 11) then
                            v.Idx := 0;
                            v.Crc := (others => '0');
                            if In_Data = r.Crc then
                                v.Fsm := Lookup_s;
                            else
                                v.EvtHdr := '1';
                                v.Fsm    := Drop_s;
                            end if;
                        end if;
                    end if;
                end if;

            when Lookup_s =>
                -- ECSS 5.3.3.9b, 5.4.3.9b: the Transaction Identifier relates the reply to its command
                v.Cnt     := (others => '0');
                v.HoldCnt := 0;
                v.Eep     := '0';
                v.Excess  := '0';
                v.CrcOk   := '0';
                v.Crc     := (others => '0');
                if Lk_Hit = '1' and Lk_Instr(5 downto 0) = r.Instr(5 downto 0) then
                    v.Fsm := Data_s;
                else
                    v.EvtUnexp := '1';
                    v.Fsm      := Drop_s;
                end if;

            when Data_s =>
                if Acc_v then
                    if In_Last = '1' then
                        v.Eep := In_Data(0);
                        if r.ReadFmt = '1' and r.Cnt <= Len_v then
                            v.Short := '1';
                        else
                            v.Short := '0';
                        end if;
                        v.Fsm := Flush_s;
                    else
                        if r.Cnt <= Len_v then
                            v.Cnt := r.Cnt + 1;
                        end if;
                        if r.ReadFmt = '1' and r.Cnt < Len_v then
                            -- Data byte, passed on two bytes later
                            v.Crc := crcUpdate(r.Crc, In_Data);
                            if r.HoldCnt = 2 then
                                v.OutValid := '1';
                                v.OutData  := r.Hold(0);
                                v.OutLast  := '0';
                                v.Hold(0)  := r.Hold(1);
                                v.Hold(1)  := In_Data;
                            else
                                v.Hold(r.HoldCnt) := In_Data;
                                v.HoldCnt         := r.HoldCnt + 1;
                            end if;
                        elsif r.ReadFmt = '1' and r.Cnt = Len_v then
                            if In_Data = r.Crc then
                                v.CrcOk := '1';
                            end if;
                        else
                            v.Excess := '1';
                        end if;
                    end if;
                end if;

            when Flush_s =>
                -- Held data bytes; the last one with TLast. In a reply that is too short the newest byte is taken
                -- as its Data CRC and not passed on.
                if r.Short = '1' and r.HoldCnt /= 0 then
                    v.HoldCnt := r.HoldCnt - 1;
                    v.Short   := '0';
                elsif r.HoldCnt = 0 then
                    v.Fsm := Conf_s;
                    if r.Eep = '1' or r.Excess = '1' or (r.ReadFmt = '1' and (r.Cnt <= Len_v or r.CrcOk = '0')) then
                        -- ECSS 5.3.3.11, 5.4.3.12: corrupted data field
                        v.DataErr := '1';
                    else
                        v.DataErr := '0';
                    end if;
                elsif Free_v then
                    v.OutValid := '1';
                    v.OutData  := r.Hold(0);
                    v.Hold(0)  := r.Hold(1);
                    v.HoldCnt  := r.HoldCnt - 1;
                    if r.HoldCnt = 1 then
                        v.OutLast := '1';
                    else
                        v.OutLast := '0';
                    end if;
                end if;

            when Conf_s =>
                if Conf_Ready = '1' then
                    v.EvtData := r.DataErr;
                    v.EvtRx   := not r.DataErr;
                    v.Fsm     := Hdr_s;
                    v.Idx     := 0;
                    v.Crc     := (others => '0');
                end if;

            when Drop_s =>
                if Acc_v and In_Last = '1' then
                    v.Fsm := Hdr_s;
                    v.Idx := 0;
                    v.Crc := (others => '0');
                end if;

            -- Recovery state for an illegal state
            -- coverage off
            when others =>
                v.Fsm := Hdr_s;
            -- coverage on

        end case;

        In_Ready <= '1' when Acc_v else '0';

        r_next <= v;
    end process;

    Lk_Tid <= r.Tid;
    -- The entry is removed in the cycle in which the reply is related to it, so its timer cannot expire while the
    -- reply is received or its confirmation waits
    Rm_Valid       <= '1' when r.Fsm = Lookup_s and Lk_Hit = '1' and Lk_Instr(5 downto 0) = r.Instr(5 downto 0) else '0';
    Rm_Tid         <= r.Tid;
    Conf_Valid     <= '1' when r.Fsm = Conf_s else '0';
    Conf_Tid       <= r.Tid;
    Conf_Status    <= r.Status;
    Conf_Instr     <= r.Instr;
    Conf_Len       <= r.Len;
    Conf_DataErr   <= r.DataErr;
    Out_Data       <= r.OutData;
    Out_Last       <= r.OutLast;
    Out_Valid      <= r.OutValid;
    Evt_HdrErr     <= r.EvtHdr;
    Evt_Unexpected <= r.EvtUnexp;
    Evt_DataErr    <= r.EvtData;
    Evt_Rx         <= r.EvtRx;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm      <= Hdr_s;
                r.Idx      <= 0;
                r.ReadFmt  <= '0';
                r.Crc      <= (others => '0');
                r.OutValid <= '0';
                r.EvtHdr   <= '0';
                r.EvtUnexp <= '0';
                r.EvtData  <= '0';
                r.EvtRx    <= '0';
            end if;
        end if;
    end process;

end architecture;
