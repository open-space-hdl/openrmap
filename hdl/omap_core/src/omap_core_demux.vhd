---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packet demultiplexer (CO-1): looks at the first three characters of a received packet (logical
-- address, Protocol Identifier, instruction) and passes the packet to the Target, the Initiator or
-- the user port, or discards it.
--
-- Documentation: hdl/omap_core/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.omap_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity omap_core_demux is
    generic (
        Target_g      : boolean := true;
        Initiator_g   : boolean := true;
        Passthrough_g : boolean := true
    );
    port (
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Received packets (N-Char stream)
        S_Pkt_TData  : in    std_logic_vector(7 downto 0);
        S_Pkt_TLast  : in    std_logic;
        S_Pkt_TValid : in    std_logic;
        S_Pkt_TReady : out   std_logic;
        -- Commands to the Target
        M_Tgt_TData  : out   std_logic_vector(7 downto 0);
        M_Tgt_TLast  : out   std_logic;
        M_Tgt_TValid : out   std_logic;
        M_Tgt_TReady : in    std_logic;
        -- Replies to the Initiator
        M_Ini_TData  : out   std_logic_vector(7 downto 0);
        M_Ini_TLast  : out   std_logic;
        M_Ini_TValid : out   std_logic;
        M_Ini_TReady : in    std_logic;
        -- Packets of other protocols to the user port
        M_Usr_TData  : out   std_logic_vector(7 downto 0);
        M_Usr_TLast  : out   std_logic;
        M_Usr_TValid : out   std_logic;
        M_Usr_TReady : in    std_logic;
        -- Events (one cycle): packet to the user port, packet of another protocol discarded, command
        -- discarded by a node without Target
        Evt_User     : out   std_logic;
        Evt_Discard  : out   std_logic;
        Evt_CmdRx    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of omap_core_demux is

    type State_t is (Head_s, Decide_s, Replay_s, Pass_s, Drop_s);

    type Dest_t is (DestTgt, DestIni, DestUsr, DestDrop);

    type Beat_t is record
        Data : std_logic_vector(7 downto 0);
        Last : std_logic;
    end record;

    type Buf_t is array (0 to 2) of Beat_t;

    type TwoProcess_r is record
        State    : State_t;
        Buf      : Buf_t;
        Num      : natural range 0 to 3;
        Idx      : natural range 0 to 2;
        Dest     : Dest_t;
        EvtUser  : std_logic;
        EvtDisc  : std_logic;
        EvtCmdRx : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Destination of a packet from its first characters (Num of them, the last one possibly the end marker)
    function destination (
        buf : Buf_t;
        num : natural) return Dest_t is
        variable Data_v : natural := 0;
    begin

        -- Number of data characters before the end marker
        for i in 0 to 2 loop
            if i < num and buf(i).Last = '0' then
                Data_v := Data_v + 1;
            end if;
        end loop;

        -- Another protocol: shorter than the Protocol Identifier or another Protocol Identifier
        if Data_v < 2 or buf(1).Data /= ProtocolId_c then
            if Passthrough_g then
                return DestUsr;
            else
                return DestDrop;
            end if;
        end if;

        -- RMAP reply (packet type 0b00): Initiator, or the Target of a Target-only node (ECSS 5.7.1.3b)
        if Data_v = 3 and buf(2).Data(7 downto 6) = "00" then
            if Initiator_g then
                return DestIni;
            else
                return DestTgt;
            end if;
        end if;

        -- RMAP command, reserved packet type, or a packet that ends before its instruction
        if Target_g then
            return DestTgt;
        elsif Data_v = 3 then
            return DestDrop; -- ECSS 5.7.1.2b
        else
            return DestIni;
        end if;
    end function;

begin

    p_comb : process (all) is
        variable v     : TwoProcess_r;
        variable Out_v : Beat_t;
        variable Val_v : std_logic;
        variable Rdy_v : std_logic;
    begin
        v          := r;
        v.EvtUser  := '0';
        v.EvtDisc  := '0';
        v.EvtCmdRx := '0';

        -- Output beat: replayed from the buffer or passed through
        if r.State = Replay_s then
            Out_v := r.Buf(r.Idx);
            Val_v := '1';
        elsif r.State = Pass_s then
            Out_v := (Data => S_Pkt_TData,
                      Last => S_Pkt_TLast);
            Val_v := S_Pkt_TValid;
        else
            Out_v := (Data => S_Pkt_TData,
                      Last => S_Pkt_TLast);
            Val_v := '0';
        end if;

        case r.Dest is

            when DestTgt =>
                Rdy_v := M_Tgt_TReady;

            when DestIni =>
                Rdy_v := M_Ini_TReady;

            when DestUsr =>
                Rdy_v := M_Usr_TReady;

            when others =>
                Rdy_v := '1';

        end case;

        M_Tgt_TData  <= Out_v.Data;
        M_Tgt_TLast  <= Out_v.Last;
        M_Ini_TData  <= Out_v.Data;
        M_Ini_TLast  <= Out_v.Last;
        M_Usr_TData  <= Out_v.Data;
        M_Usr_TLast  <= Out_v.Last;
        M_Tgt_TValid <= '0';
        M_Ini_TValid <= '0';
        M_Usr_TValid <= '0';

        case r.Dest is

            when DestTgt =>
                M_Tgt_TValid <= Val_v;

            when DestIni =>
                M_Ini_TValid <= Val_v;

            when DestUsr =>
                M_Usr_TValid <= Val_v;

            when others =>
                null;

        end case;

        S_Pkt_TReady <= '0';

        case r.State is

            -- Collect up to three data characters or the end marker of a shorter packet
            when Head_s =>
                S_Pkt_TReady <= '1';
                if S_Pkt_TValid = '1' then
                    v.Buf(r.Num) := (Data => S_Pkt_TData,
                                     Last => S_Pkt_TLast);
                    v.Num        := r.Num + 1;
                    if S_Pkt_TLast = '1' or r.Num = 2 then
                        v.State := Decide_s;
                    end if;
                end if;

            when Decide_s =>
                v.Dest := destination(r.Buf, r.Num);
                v.Idx  := 0;
                if v.Dest = DestDrop then
                    -- Three data characters and the Protocol Identifier: a command at an Initiator-only node
                    if r.Num = 3 and r.Buf(2).Last = '0' and r.Buf(1).Data = ProtocolId_c then
                        v.EvtCmdRx := '1';
                    else
                        v.EvtDisc := '1';
                    end if;
                    if r.Buf(r.Num - 1).Last = '1' then
                        v.State := Head_s;
                        v.Num   := 0;
                    else
                        v.State := Drop_s;
                    end if;
                else
                    if v.Dest = DestUsr then
                        v.EvtUser := '1';
                    end if;
                    v.State := Replay_s;
                end if;

            -- Buffered characters to the destination
            when Replay_s =>
                if Rdy_v = '1' then
                    if r.Idx = r.Num - 1 then
                        v.Num := 0;
                        if r.Buf(r.Idx).Last = '1' then
                            v.State := Head_s;
                        else
                            v.State := Pass_s;
                        end if;
                    else
                        v.Idx := r.Idx + 1;
                    end if;
                end if;

            -- Rest of the packet to the destination
            when Pass_s =>
                S_Pkt_TReady <= Rdy_v;
                if S_Pkt_TValid = '1' and Rdy_v = '1' and S_Pkt_TLast = '1' then
                    v.State := Head_s;
                end if;

            -- Rest of a discarded packet
            when Drop_s =>
                S_Pkt_TReady <= '1';
                if S_Pkt_TValid = '1' and S_Pkt_TLast = '1' then
                    v.State := Head_s;
                    v.Num   := 0;
                end if;

            -- coverage off
            when others =>
                v.State := Drop_s; -- recovery (D12): discard up to the next end of packet
                v.Num   := 0;
            -- coverage on

        end case;

        r_next <= v;
    end process;

    Evt_User    <= r.EvtUser;
    Evt_Discard <= r.EvtDisc;
    Evt_CmdRx   <= r.EvtCmdRx;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Head_s;
                r.Num      <= 0;
                r.Idx      <= 0;
                r.Dest     <= DestDrop;
                r.EvtUser  <= '0';
                r.EvtDisc  <= '0';
                r.EvtCmdRx <= '0';
            end if;
        end if;
    end process;

end architecture;
