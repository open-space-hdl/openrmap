---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Command decoder of the RMAP target (TG-1): decodes the command header from the N-Char stream,
-- checks the Header CRC, passes the header to the controller and then classifies the rest of the
-- packet: data bytes of the data field (passed on), Data CRC (checked), excess data and the end of
-- the packet. Packets with an incomplete header, a Header CRC error or packet type 0b00 are
-- discarded and reported as events.
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
entity orm_tgt_rx is
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Command packets (N-Char stream)
        In_Data       : in    std_logic_vector(7 downto 0);
        In_Last       : in    std_logic;
        In_Valid      : in    std_logic;
        In_Ready      : out   std_logic;
        -- Header with a correct Header CRC
        Hdr_Valid     : out   std_logic;
        Hdr_Ready     : in    std_logic;
        Hdr           : out   CmdHeader_t;
        -- Data bytes of the data field (write and read-modify-write commands)
        Data_Valid    : out   std_logic;
        Data_Ready    : in    std_logic;
        Data_Byte     : out   std_logic_vector(7 downto 0);
        -- End of the packet after a header with a correct Header CRC
        End_Valid     : out   std_logic;
        End_Ready     : in    std_logic;
        End_Eep       : out   std_logic; -- Packet ended with an EEP
        End_Immediate : out   std_logic; -- No character between the Header CRC and the end of the packet
        End_Early     : out   std_logic; -- Data CRC not received (write and read-modify-write)
        End_Excess    : out   std_logic; -- Characters after the Data CRC, or after the header of a read
        End_CrcOk     : out   std_logic; -- Data CRC received and correct
        -- Discarded packets (one-cycle events)
        Evt_HdrCrc    : out   std_logic; -- Header CRC error
        Evt_HdrShort  : out   std_logic; -- End of the packet before the Header CRC
        Evt_ReplyRx   : out   std_logic  -- Packet type 0b00 (reply)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_tgt_rx is

    type Fsm_t is (Hdr_s, HdrOut_s, Data_s, EndOut_s, Drop_s);

    type TwoProcess_r is record
        Fsm       : Fsm_t;
        Idx       : natural range 0 to 31;    -- Header byte index
        RaBytes   : natural range 0 to 12;
        Crc       : std_logic_vector(7 downto 0);
        H         : CmdHeader_t;
        HasData   : std_logic;
        Cnt       : unsigned(24 downto 0);    -- Characters after the header (saturates above Data Length + 1)
        DataValid : std_logic;
        DataByte  : std_logic_vector(7 downto 0);
        Eep       : std_logic;
        Immediate : std_logic;
        Early     : std_logic;
        Excess    : std_logic;
        CrcOk     : std_logic;
        EvtCrc    : std_logic;
        EvtShort  : std_logic;
        EvtReply  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v     : TwoProcess_r;
        variable Acc_v : boolean; -- Character accepted in this cycle
        variable Rel_v : integer range -16 to 31;
    begin
        v          := r;
        v.EvtCrc   := '0';
        v.EvtShort := '0';
        v.EvtReply := '0';

        if Data_Ready = '1' then
            v.DataValid := '0';
        end if;

        -- Characters are accepted in the header, the data field (when the data register is free) and while
        -- dropping
        Acc_v := In_Valid = '1' and (r.Fsm = Hdr_s or r.Fsm = Drop_s or
                                     (r.Fsm = Data_s and (r.DataValid = '0' or Data_Ready = '1')));

        -- Position after the Reply Address: 0 Initiator Logical Address ... 11 Header CRC
        Rel_v := r.Idx - 4 - r.RaBytes;

        case r.Fsm is

            when Hdr_s =>
                if Acc_v then
                    if In_Last = '1' then
                        -- ECSS 5.3.3.4.2: end of the packet before the Header CRC
                        v.EvtShort := '1';
                        v.Idx      := 0;
                        v.Crc      := (others => '0');
                    else
                        v.Idx := r.Idx + 1;
                        if r.Idx < 4 + r.RaBytes + 11 then
                            v.Crc := crcUpdate(r.Crc, In_Data);
                        end if;

                        if r.Idx = 0 then
                            v.H       := CmdHeaderInit_c;
                            v.H.Tla   := In_Data;
                            v.RaBytes := 0;
                        elsif r.Idx = 1 then
                            -- ECSS 5.3.3.4.1: only packets with the Protocol Identifier of RMAP are decoded
                            if In_Data /= ProtocolId_c then
                                v.Fsm := Drop_s;
                            end if;
                        elsif r.Idx = 2 then
                            v.H.Instr := In_Data;
                            v.RaBytes := replyAddrBytes(In_Data);
                            -- ECSS 5.7.1.3b: a reply at the target is discarded
                            if In_Data(InstrReserved_c) = '0' and In_Data(InstrCommand_c) = '0' then
                                v.EvtReply := '1';
                                v.Fsm      := Drop_s;
                            end if;
                        elsif r.Idx = 3 then
                            v.H.Key := In_Data;
                        elsif Rel_v < 0 then
                            v.H.ReplyAddr := r.H.ReplyAddr(ReplyAddrMax_c * 8 - 9 downto 0) & In_Data;
                        else

                            case Rel_v is

                                when 0 =>
                                    v.H.Ila := In_Data;

                                when 1 =>
                                    v.H.Tid(15 downto 8) := In_Data;

                                when 2 =>
                                    v.H.Tid(7 downto 0) := In_Data;

                                when 3 =>
                                    v.H.Addr(39 downto 32) := In_Data;

                                when 4 =>
                                    v.H.Addr(31 downto 24) := In_Data;

                                when 5 =>
                                    v.H.Addr(23 downto 16) := In_Data;

                                when 6 =>
                                    v.H.Addr(15 downto 8) := In_Data;

                                when 7 =>
                                    v.H.Addr(7 downto 0) := In_Data;

                                when 8 =>
                                    v.H.Len(23 downto 16) := In_Data;

                                when 9 =>
                                    v.H.Len(15 downto 8) := In_Data;

                                when 10 =>
                                    v.H.Len(7 downto 0) := In_Data;

                                when others =>
                                    -- Header CRC (ECSS 5.3.3.4.4, 5.3.3.4.5)
                                    v.Idx := 0;
                                    v.Crc := (others => '0');
                                    if In_Data = r.Crc then
                                        v.Fsm := HdrOut_s;
                                    else
                                        v.EvtCrc := '1';
                                        v.Fsm    := Drop_s;
                                    end if;

                            end case;

                        end if;
                    end if;
                end if;

            when HdrOut_s =>
                if Hdr_Ready = '1' then
                    v.Fsm       := Data_s;
                    v.Cnt       := (others => '0');
                    v.Crc       := (others => '0');
                    v.Immediate := '1';
                    v.Excess    := '0';
                    v.CrcOk     := '0';
                    -- Write and read-modify-write commands have a data field (ECSS 5.3.1, 5.5.1)
                    if r.H.Instr(InstrReserved_c downto InstrCommand_c) = "01" and
                       (cmdKind(cmdCode(r.H.Instr)) = CmdWrite or cmdKind(cmdCode(r.H.Instr)) = CmdRmw) then
                        v.HasData := '1';
                    else
                        v.HasData := '0';
                    end if;
                end if;

            when Data_s =>
                if Acc_v then
                    if In_Last = '1' then
                        v.Eep := In_Data(0);
                        if r.HasData = '1' and r.Cnt <= unsigned('0' & r.H.Len) then
                            v.Early := '1';
                        else
                            v.Early := '0';
                        end if;
                        v.Fsm := EndOut_s;
                    else
                        v.Immediate := '0';
                        if r.Cnt <= unsigned('0' & r.H.Len) then
                            v.Cnt := r.Cnt + 1;
                        end if;
                        if r.HasData = '1' and r.Cnt < unsigned('0' & r.H.Len) then
                            v.DataValid := '1';
                            v.DataByte  := In_Data;
                            v.Crc       := crcUpdate(r.Crc, In_Data);
                        elsif r.HasData = '1' and r.Cnt = unsigned('0' & r.H.Len) then
                            -- Data CRC (ECSS 5.1.15)
                            if In_Data = r.Crc then
                                v.CrcOk := '1';
                            end if;
                        else
                            v.Excess := '1';
                        end if;
                    end if;
                end if;

            when EndOut_s =>
                if End_Ready = '1' then
                    v.Fsm := Hdr_s;
                    v.Idx := 0;
                    v.Crc := (others => '0');
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

        if Acc_v then
            In_Ready <= '1';
        else
            In_Ready <= '0';
        end if;

        r_next <= v;
    end process;

    Hdr           <= r.H;
    Hdr_Valid     <= '1' when r.Fsm = HdrOut_s else '0';
    Data_Valid    <= r.DataValid;
    Data_Byte     <= r.DataByte;
    End_Valid     <= '1' when r.Fsm = EndOut_s and r.DataValid = '0' else '0';
    End_Eep       <= r.Eep;
    End_Immediate <= r.Immediate;
    End_Early     <= r.Early;
    End_Excess    <= r.Excess;
    End_CrcOk     <= r.CrcOk;
    Evt_HdrCrc    <= r.EvtCrc;
    Evt_HdrShort  <= r.EvtShort;
    Evt_ReplyRx   <= r.EvtReply;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fsm       <= Hdr_s;
                r.Idx       <= 0;
                r.RaBytes   <= 0;
                r.Crc       <= (others => '0');
                r.DataValid <= '0';
                r.EvtCrc    <= '0';
                r.EvtShort  <= '0';
                r.EvtReply  <= '0';
            end if;
        end if;
    end process;

end architecture;
