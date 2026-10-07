---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types and constants of the MIB testbench: inputs driven by the sequencer and observed outputs.
--
-- Documentation: hdl/orm_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.orm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package orm_mib_tb_pkg is

    -- Event inputs (one cycle each)
    constant EvHdrCrc_c     : natural := 0;
    constant EvHdrShort_c   : natural := 1;
    constant EvReplyRx_c    : natural := 2;
    constant EvRepSent_c    : natural := 3;
    constant EvCmdSent_c    : natural := 4;
    constant EvRepOk_c      : natural := 5;
    constant EvHdrErr_c     : natural := 6;
    constant EvDataErr_c    : natural := 7;
    constant EvUnexpected_c : natural := 8;
    constant EvTimeout_c    : natural := 9;
    constant EvTidBusy_c    : natural := 10;
    constant EvUser_c       : natural := 11;
    constant EvDiscard_c    : natural := 12;
    constant EvCmdRx_c      : natural := 13;

    -- Inputs of the MIB driven by the test sequencer
    type MibIn_t is record
        IndValid   : std_logic;
        IndInstr   : std_logic_vector(7 downto 0);
        IndStatus  : std_logic_vector(7 downto 0);
        IndIla     : std_logic_vector(7 downto 0);
        IndTid     : std_logic_vector(15 downto 0);
        IndAddr    : std_logic_vector(39 downto 0);
        IndReplied : std_logic;
        Ev         : std_logic_vector(13 downto 0);
        IniOpen    : std_logic_vector(7 downto 0);
        EccSec     : std_logic_vector(2 downto 0);
        EccDed     : std_logic_vector(2 downto 0);
        -- '1': the harness pulses the events "command sent" and "reply confirmed" in the cycle in which the
        -- register file executes a write
        OnWrite    : std_logic;
    end record;

    constant MibInInit_c : MibIn_t := (
        IndValid   => '0',
        IndInstr   => (others => '0'),
        IndStatus  => (others => '0'),
        IndIla     => (others => '0'),
        IndTid     => (others => '0'),
        IndAddr    => (others => '0'),
        IndReplied => '0',
        Ev         => (others => '0'),
        IniOpen    => (others => '0'),
        EccSec     => (others => '0'),
        EccDed     => (others => '0'),
        OnWrite    => '0'
    );

    type Natural3_t is array (0 to 2) of natural;

    -- Observed outputs: configuration and the injection commands per channel
    type MibOut_t is record
        La0        : std_logic_vector(7 downto 0);
        La0En      : std_logic;
        La1        : std_logic_vector(7 downto 0);
        La1En      : std_logic;
        DefLaEn    : std_logic;
        Key        : std_logic_vector(7 downto 0);
        KeyEn      : std_logic;
        Win        : WinCfgArray_t(0 to WinMax_c - 1);
        TickCycles : std_logic_vector(15 downto 0);
        Timeout    : std_logic_vector(15 downto 0);
        Irq        : std_logic;
        CntInj     : Natural3_t;
        LastDouble : std_logic;
    end record;

    -- AXI4-Lite VVC instance
    constant Axi_c : natural := 0;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body orm_mib_tb_pkg is

end package body;
