---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Transaction table of the RMAP initiator (IN-3): holds the outstanding commands with reply
-- (Transaction Identifier, instruction, remaining time), tells the encoder whether an entry is free
-- and whether a Transaction Identifier is in use, finds the entry of a reply, removes completed
-- entries and reports entries whose reply did not arrive within the timeout.
--
-- Documentation: hdl/orm_ini/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity orm_ini_tt is
    generic (
        Transactions_g : positive := 8
    );
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Configuration: tick period in clock cycles (0 = every cycle), timeout in ticks (0 = no timeout)
        Cfg_TickCycles : in    std_logic_vector(15 downto 0);
        Cfg_Timeout    : in    std_logic_vector(15 downto 0);
        -- Registration (encoder)
        Reg_Valid      : in    std_logic;
        Reg_Tid        : in    std_logic_vector(15 downto 0);
        Reg_Instr      : in    std_logic_vector(7 downto 0);
        Reg_Ready      : out   std_logic; -- A free entry
        Reg_Busy       : out   std_logic; -- Reg_Tid is in use
        -- Lookup and removal (decoder): Rm_Valid in the cycle of the lookup of Rm_Tid
        Lk_Tid         : in    std_logic_vector(15 downto 0);
        Lk_Hit         : out   std_logic;
        Lk_Instr       : out   std_logic_vector(7 downto 0);
        Rm_Valid       : in    std_logic;
        Rm_Tid         : in    std_logic_vector(15 downto 0);
        -- Expired entries
        To_Valid       : out   std_logic;
        To_Ready       : in    std_logic;
        To_Tid         : out   std_logic_vector(15 downto 0);
        To_Instr       : out   std_logic_vector(7 downto 0);
        -- Number of outstanding entries
        Stat_Open      : out   std_logic_vector(7 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of orm_ini_tt is

    type Tid_t is array (0 to Transactions_g - 1) of std_logic_vector(15 downto 0);
    type Instr_t is array (0 to Transactions_g - 1) of std_logic_vector(7 downto 0);
    type Timer_t is array (0 to Transactions_g - 1) of unsigned(15 downto 0);

    type TwoProcess_r is record
        Valid   : std_logic_vector(Transactions_g - 1 downto 0);
        Expired : std_logic_vector(Transactions_g - 1 downto 0);
        Tid     : Tid_t;
        Instr   : Instr_t;
        Timer   : Timer_t;
        TickCnt : unsigned(15 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Tick_v : boolean;
        variable Free_v : integer range -1 to Transactions_g - 1;
        variable Exp_v  : integer range -1 to Transactions_g - 1;
        variable Hit_v  : boolean;
        variable Open_v : natural range 0 to Transactions_g;
    begin
        v := r;

        -- Tick
        Tick_v := r.TickCnt = 0;
        if Tick_v then
            v.TickCnt := unsigned(Cfg_TickCycles);
        else
            v.TickCnt := r.TickCnt - 1;
        end if;

        -- Lowest free entry, lowest expired entry, entry of Reg_Tid, entry of Lk_Tid
        Free_v   := -1;
        Exp_v    := -1;
        Reg_Busy <= '0';
        Lk_Hit   <= '0';
        Lk_Instr <= (others => '0');
        Open_v   := 0;

        for i in Transactions_g - 1 downto 0 loop
            if r.Valid(i) = '0' then
                Free_v := i;
            else
                Open_v := Open_v + 1;
                if r.Expired(i) = '1' then
                    Exp_v := i;
                end if;
                if r.Tid(i) = Reg_Tid then
                    Reg_Busy <= '1';
                end if;
                if r.Tid(i) = Lk_Tid and r.Expired(i) = '0' then
                    Lk_Hit   <= '1';
                    Lk_Instr <= r.Instr(i);
                end if;
            end if;
        end loop;

        Reg_Ready <= '1' when Free_v >= 0 else '0';
        Stat_Open <= std_logic_vector(to_unsigned(Open_v, 8));

        -- Timers (ECSS 4.3.1: reply timeout of the initiator)
        for i in 0 to Transactions_g - 1 loop
            if Tick_v and r.Valid(i) = '1' and r.Expired(i) = '0' and unsigned(Cfg_Timeout) /= 0 then
                if r.Timer(i) <= 1 then
                    v.Expired(i) := '1';
                else
                    v.Timer(i) := r.Timer(i) - 1;
                end if;
            end if;
        end loop;

        -- Removal of the command of a reply, in the cycle of its lookup: a timer that expires in this cycle is void
        if Rm_Valid = '1' then

            for i in 0 to Transactions_g - 1 loop
                if r.Valid(i) = '1' and r.Expired(i) = '0' and r.Tid(i) = Rm_Tid then
                    v.Valid(i)   := '0';
                    v.Expired(i) := '0';
                end if;
            end loop;

        end if;

        -- Removal of a reported expired entry
        if Exp_v >= 0 then
            To_Valid <= '1';
            To_Tid   <= r.Tid(Exp_v);
            To_Instr <= r.Instr(Exp_v);
            if To_Ready = '1' then
                v.Valid(Exp_v)   := '0';
                v.Expired(Exp_v) := '0';
            end if;
        else
            To_Valid <= '0';
            To_Tid   <= (others => '0');
            To_Instr <= (others => '0');
        end if;

        -- Registration
        if Reg_Valid = '1' and Free_v >= 0 then
            v.Valid(Free_v)   := '1';
            v.Expired(Free_v) := '0';
            v.Tid(Free_v)     := Reg_Tid;
            v.Instr(Free_v)   := Reg_Instr;
            v.Timer(Free_v)   := unsigned(Cfg_Timeout);
        end if;

        r_next <= v;
    end process;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Valid   <= (others => '0');
                r.Expired <= (others => '0');
                r.TickCnt <= (others => '0');
            end if;
        end if;
    end process;

end architecture;
