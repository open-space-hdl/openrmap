---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packet multiplexer (CO-2): merges the replies of the target, the commands of the initiator and
-- the packets of the user port into the transmitted packet stream, one complete packet at a time.
-- The next source is chosen round robin by olo_base_arb_rr when a packet starts.
--
-- Documentation: hdl/orm_core/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_core_mux is
    port (
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Sources (N-Char streams): replies of the target, commands of the initiator, user packets
        S_Tgt_TData  : in    std_logic_vector(7 downto 0);
        S_Tgt_TLast  : in    std_logic;
        S_Tgt_TValid : in    std_logic;
        S_Tgt_TReady : out   std_logic;
        S_Ini_TData  : in    std_logic_vector(7 downto 0);
        S_Ini_TLast  : in    std_logic;
        S_Ini_TValid : in    std_logic;
        S_Ini_TReady : out   std_logic;
        S_Usr_TData  : in    std_logic_vector(7 downto 0);
        S_Usr_TLast  : in    std_logic;
        S_Usr_TValid : in    std_logic;
        S_Usr_TReady : out   std_logic;
        -- Transmitted packets (N-Char stream)
        M_Pkt_TData  : out   std_logic_vector(7 downto 0);
        M_Pkt_TLast  : out   std_logic;
        M_Pkt_TValid : out   std_logic;
        M_Pkt_TReady : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_core_mux is

    type TwoProcess_r is record
        Busy : std_logic;                    -- A packet is being passed
        Sel  : std_logic_vector(2 downto 0); -- Source of the packet: bit 2 target, 1 initiator, 0 user
    end record;

    signal r, r_next : TwoProcess_r;

    signal Req      : std_logic_vector(2 downto 0);
    signal Grant    : std_logic_vector(2 downto 0);
    signal ArbValid : std_logic;
    signal ArbReady : std_logic;

begin

    Req <= (S_Tgt_TValid & S_Ini_TValid & S_Usr_TValid) when r.Busy = '0' else "000";

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Valid_v : std_logic;
        variable Last_v  : std_logic;
    begin
        v        := r;
        ArbReady <= '0';

        -- Start of a packet: the granted source is locked until its end marker
        if r.Busy = '0' and ArbValid = '1' then
            v.Busy   := '1';
            v.Sel    := Grant;
            ArbReady <= '1';
        end if;

        -- Output multiplexer
        if r.Sel(2) = '1' then
            M_Pkt_TData <= S_Tgt_TData;
            Last_v      := S_Tgt_TLast;
            Valid_v     := S_Tgt_TValid;
        elsif r.Sel(1) = '1' then
            M_Pkt_TData <= S_Ini_TData;
            Last_v      := S_Ini_TLast;
            Valid_v     := S_Ini_TValid;
        else
            M_Pkt_TData <= S_Usr_TData;
            Last_v      := S_Usr_TLast;
            Valid_v     := S_Usr_TValid;
        end if;
        Valid_v      := Valid_v and r.Busy;
        M_Pkt_TLast  <= Last_v;
        M_Pkt_TValid <= Valid_v;
        S_Tgt_TReady <= M_Pkt_TReady and r.Busy and r.Sel(2);
        S_Ini_TReady <= M_Pkt_TReady and r.Busy and r.Sel(1);
        S_Usr_TReady <= M_Pkt_TReady and r.Busy and r.Sel(0);

        -- End of the packet
        if Valid_v = '1' and M_Pkt_TReady = '1' and Last_v = '1' then
            v.Busy := '0';
        end if;

        r_next <= v;
    end process;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Busy <= '0';
                r.Sel  <= "000";
            end if;
        end if;
    end process;

    i_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => 3
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => Req,
            Out_Grant => Grant,
            Out_Ready => ArbReady,
            Out_Valid => ArbValid
        );

end architecture;
