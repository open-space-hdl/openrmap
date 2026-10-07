---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types of the initiator testbench: request descriptor, configuration and the observations of the
-- harness (confirmations and events).
--
-- Documentation: hdl/orm_ini/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package orm_ini_tb_pkg is

    -- VVC instances
    constant VvcData_c    : natural := 0; -- AXI4-Stream master: write data
    constant VvcCmd_c     : natural := 1; -- AXI4-Stream slave: commands
    constant VvcRep_c     : natural := 2; -- AXI4-Stream master: replies
    constant VvcRepData_c : natural := 3; -- AXI4-Stream slave: reply data

    -- Request descriptor
    type IniReq_t is record
        Valid        : std_logic;
        Code         : std_logic_vector(3 downto 0);
        TgtAddr      : std_logic_vector(63 downto 0);
        TgtAddrLen   : natural;
        Tla          : std_logic_vector(7 downto 0);
        Key          : std_logic_vector(7 downto 0);
        ReplyAddr    : std_logic_vector(95 downto 0);
        ReplyAddrLen : natural;
        Ila          : std_logic_vector(7 downto 0);
        Tid          : std_logic_vector(15 downto 0);
        Addr         : std_logic_vector(39 downto 0);
        Len          : std_logic_vector(23 downto 0);
    end record;

    constant IniReqInit_c : IniReq_t := (
        Valid        => '0',
        Code         => "0011",
        TgtAddr      => (others => '0'),
        TgtAddrLen   => 0,
        Tla          => x"FE",
        Key          => x"00",
        ReplyAddr    => (others => '0'),
        ReplyAddrLen => 0,
        Ila          => x"67",
        Tid          => x"0000",
        Addr         => (others => '0'),
        Len          => (others => '0')
    );

    -- Configuration
    type IniCfg_t is record
        TickCycles : std_logic_vector(15 downto 0);
        Timeout    : std_logic_vector(15 downto 0);
        ConfReady  : std_logic;
    end record;

    constant IniCfgInit_c : IniCfg_t := (
        TickCycles => x"0009", -- Tick every 10 cycles (100 ns)
        Timeout    => x"0000",
        ConfReady  => '1'
    );

    -- Confirmation log
    type IniConf_t is record
        Tid    : std_logic_vector(15 downto 0);
        Instr  : std_logic_vector(7 downto 0);
        Status : std_logic_vector(7 downto 0);
        Len    : std_logic_vector(23 downto 0);
        Error  : std_logic_vector(1 downto 0);
    end record;

    type IniConfArray_t is array (0 to 63) of IniConf_t;

    type IniObs_t is record
        ReqReady   : std_logic;
        ConfCnt    : natural;
        Conf       : IniConfArray_t;
        CmdSentCnt : natural;
        RepOkCnt   : natural;
        HdrErrCnt  : natural;
        DataErrCnt : natural;
        UnexpCnt   : natural;
        TimeoutCnt : natural;
        TidBusyCnt : natural;
        OpenCnt    : natural;
        ConfValid  : std_logic;
    end record;

end package;
