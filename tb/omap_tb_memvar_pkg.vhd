---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- The memory object of the AXI memory models (one instance per model, see omap_tb_mem_pkg), in a
-- package of its own: a shared variable of a protected type is declared after the protected body.
--
-- Documentation: hdl/omap_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library work;
    use work.omap_tb_mem_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package omap_tb_memvar_pkg is

    shared variable Mem_v : TbMem_t;

end package;
