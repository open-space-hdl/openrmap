---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenRMAP testbenches (VUnit runner plus UVVM).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package omap_tb_pkg is

    -- AXI-Stream BFM configuration of the OpenRMAP testbenches: element bits map 1:1 to TDATA
    -- (LOWER_BYTE_RIGHT) and the timeouts suit long packets.
    constant OmapAxisBfmConfig_c : t_axistream_bfm_config := (
        max_wait_cycles                => 1000000,
        max_wait_cycles_severity       => error,
        clock_period                   => C_UNDEFINED_TIME,
        clock_period_margin            => 0 ns,
        clock_margin_severity          => TB_ERROR,
        setup_time                     => C_UNDEFINED_TIME,
        hold_time                      => C_UNDEFINED_TIME,
        bfm_sync                       => SYNC_ON_CLOCK_ONLY,
        match_strictness               => MATCH_EXACT,
        byte_endianness                => LOWER_BYTE_RIGHT,
        valid_low_at_word_num          => 0,
        valid_low_multiple_random_prob => 0.5,
        valid_low_duration             => 0,
        valid_low_max_random_duration  => 5,
        check_packet_length            => false,
        protocol_error_severity        => error,
        ready_low_at_word_num          => 0,
        ready_low_multiple_random_prob => 0.5,
        ready_low_duration             => 0,
        ready_low_max_random_duration  => 5,
        ready_default_value            => '0',
        id_for_bfm                     => ID_BFM
    );

    -- Ends a test: prints the UVVM alert summary, stops the simulation with a failure when the alert counters
    -- differ from the expected alerts (an unexpected alert or an expected alert that did not occur), whatever the
    -- stop limits of the test, which fails the VUnit test, and hands over to the VUnit runner.
    procedure omapTestEnd (signal runner : inout runner_sync_t);

    -- Packet of data bytes followed by its end of packet marker (0x00 EOP, 0x01 EEP) as the byte array of the
    -- AXI4-Stream VVCs: the last element is the marker beat with TLast set.
    function omapPacket (
        data : in t_slv_array;
        eep  : in boolean := false) return t_slv_array;

    -- Packet of n bytes with the values (first + i) mod 256
    function omapCountPacket (
        n     : in natural;
        first : in natural := 0;
        eep   : in boolean := false) return t_slv_array;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body omap_tb_pkg is

    procedure omapTestEnd (signal runner : inout runner_sync_t) is
        variable Mismatch_v : boolean := false;
    begin
        report_alert_counters(FINAL);

        -- The alert counters are compared here, for the levels UVVM uses for its end status, so the result does
        -- not depend on when UVVM updates its end status (shared_uvvm_status)
        for L in WARNING to TB_FAILURE loop

            if L /= MANUAL_CHECK and get_alert_counter(L, REGARD) /= get_alert_counter(L, EXPECT) then
                Mismatch_v := true;
                log(ID_SEQUENCER, t_alert_level'image(L) & ": " & integer'image(get_alert_counter(L, REGARD))
                                  & " alerts, " & integer'image(get_alert_counter(L, EXPECT)) & " expected",
                    "omapTestEnd");
            end if;

        end loop;

        -- A failure ends the simulation, whatever the stop limits of the test
        assert not Mismatch_v
            report "omapTestEnd: the alerts of the test differ from the expected alerts (summary above)"
            severity failure;
        test_runner_cleanup(runner);
    end procedure;

    function omapPacket (
        data : in t_slv_array;
        eep  : in boolean := false) return t_slv_array is
        variable Arr_v : t_slv_array(0 to data'length)(7 downto 0);
    begin

        for i in 0 to data'length - 1 loop
            Arr_v(i) := data(data'low + i);
        end loop;

        if eep then
            Arr_v(data'length) := x"01";
        else
            Arr_v(data'length) := x"00";
        end if;
        return Arr_v;
    end function;

    function omapCountPacket (
        n     : in natural;
        first : in natural := 0;
        eep   : in boolean := false) return t_slv_array is
        variable Arr_v : t_slv_array(0 to n)(7 downto 0);
    begin

        for i in 0 to n - 1 loop
            Arr_v(i) := std_logic_vector(to_unsigned((first + i) mod 256, 8));
        end loop;

        if eep then
            Arr_v(n) := x"01";
        else
            Arr_v(n) := x"00";
        end if;
        return Arr_v;
    end function;

end package body;
