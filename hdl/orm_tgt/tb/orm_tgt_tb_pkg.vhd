---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types of the target testbench: configuration driven by the test sequencer and observations of
-- the harness (indications, events, external authorisation requests).
--
-- Documentation: hdl/orm_tgt/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.orm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package orm_tgt_tb_pkg is

    -- VVC instances
    constant VvcCmd_c : natural := 0; -- AXI4-Stream master: commands
    constant VvcRep_c : natural := 1; -- AXI4-Stream slave: replies

    -- Configuration of the target and of the external authorisation responder
    type TgtCfg_t is record
        La0        : std_logic_vector(7 downto 0);
        La0En      : std_logic;
        La1        : std_logic_vector(7 downto 0);
        La1En      : std_logic;
        DefLaEn    : std_logic;
        Key        : std_logic_vector(7 downto 0);
        KeyEn      : std_logic;
        Win        : WinCfgArray_t(0 to 3);
        AuthAccept : std_logic;
        AuthDelay  : natural;
        ErrInj     : std_logic_vector(2 downto 0);
        ErrDouble  : std_logic;
        -- '1': the harness drops the characters of the command VVC, takes and drops the replies
        DropCmd    : std_logic;
        DropRep    : std_logic;
    end record;

    constant TgtCfgInit_c : TgtCfg_t := (
        La0        => x"42",
        La0En      => '1',
        La1        => x"43",
        La1En      => '0',
        DefLaEn    => '1',
        Key        => x"00",
        KeyEn      => '1',
        Win        => (0 => WinOpen_c, others => WinDisabled_c),
        AuthAccept => '1',
        AuthDelay  => 3,
        ErrInj     => "000",
        ErrDouble  => '0',
        DropCmd    => '0',
        DropRep    => '0'
    );

    -- Observations of the harness
    type TgtObs_t is record
        IndCnt      : natural;
        IndTla      : std_logic_vector(7 downto 0);
        IndInstr    : std_logic_vector(7 downto 0);
        IndIla      : std_logic_vector(7 downto 0);
        IndTid      : std_logic_vector(15 downto 0);
        IndAddr     : std_logic_vector(39 downto 0);
        IndLen      : std_logic_vector(23 downto 0);
        IndStatus   : std_logic_vector(7 downto 0);
        IndReplied  : std_logic;
        HdrCrcCnt   : natural;
        HdrShortCnt : natural;
        ReplyRxCnt  : natural;
        RepSentCnt  : natural;
        AuthCnt     : natural;
        AuthInstr   : std_logic_vector(7 downto 0);
        AuthAddr    : std_logic_vector(39 downto 0);
        AuthLen     : std_logic_vector(23 downto 0);
        SecCnt      : natural;
        DedCnt      : natural;
        RepValid    : std_logic;
    end record;

    -- Enabled window with permissions (read, write, verified-only, read-modify-write, single address)
    function tbWin (
        perm : std_logic_vector(4 downto 0);
        base : std_logic_vector(39 downto 0);
        last : std_logic_vector(39 downto 0)) return WinCfg_t;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body orm_tgt_tb_pkg is

    function tbWin (
        perm : std_logic_vector(4 downto 0);
        base : std_logic_vector(39 downto 0);
        last : std_logic_vector(39 downto 0)) return WinCfg_t is
        variable Win_v : WinCfg_t;
    begin
        Win_v.Enable       := '1';
        Win_v.Read         := perm(4);
        Win_v.Write        := perm(3);
        Win_v.VerifiedOnly := perm(2);
        Win_v.Rmw          := perm(1);
        Win_v.Single       := perm(0);
        Win_v.Base         := base;
        Win_v.Last         := last;
        return Win_v;
    end function;

end package body;
