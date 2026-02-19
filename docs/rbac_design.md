# Snowflake EDW — Role & Database Hierarchy

> **Legend**
> - Thin arrow `——▶` = role inherited (granted to parent)
> - Thick arrow `══▶` = ownership
> - Dashed arrow `- - ▶` = privilege grant on object

```mermaid
%%{init: {"flowchart": {"defaultRenderer": "elk", "rankSpacing": 60, "nodeSpacing": 30}} }%%
graph TD

    SECADMIN(["SECURITYADMIN"])
    SYSADMIN(["SYSADMIN"])

    subgraph FUNC["Account Functional Roles"]
        ADMIN["SNOW_D_ADMIN<br/>Delegated Admin"]
        DEPLOY["SNOW_D_DEPLOY<br/>Deploy Admin"]
        WRITE["SNOW_D_WRITE<br/>Data Engineering"]
        READ["SNOW_D_READ<br/>Read Only"]
        ADMIN --> DEPLOY --> WRITE --> READ
    end

    SYSADMIN --> ADMIN
    SECADMIN ==> ADMIN
    SECADMIN ==> DEPLOY
    SECADMIN ==> WRITE
    SECADMIN ==> READ

    subgraph WH_GRP["Warehouse"]
        WH[("SNOW_D_ADHOC<br/>XSmall · AutoSuspend 60s")]
        warO["_WH_O_SNOW_D_ADHOC<br/>Operate + Modify"]
        warU["_WH_U_SNOW_D_ADHOC<br/>Monitor + Usage"]
        warO --> warU
        warO -. "OPERATE, MODIFY" .-> WH
        warU -. "MONITOR, USAGE" .-> WH
    end

    WRITE --> warO
    DEPLOY --> warO
    READ --> warU
    ADMIN ==> WH
    ADMIN ==> warO
    ADMIN ==> warU

    subgraph SNOW_D_RAW["SNOW_D_RAW — Ingestion Zone"]
        RAW_DB[("SNOW_D_RAW")]
        RAW_C["DB_C"]
        RAW_W["DB_W"]
        RAW_R["DB_R"]
        subgraph SC_RAW_TPCH["Schema: TPCH"]
            R_SC_C["SC_C_TPCH<br/>DDL"]
            R_SC_W["SC_W_TPCH<br/>DML"]
            R_SC_R["SC_R_TPCH<br/>SELECT"]
            R_SC_C --> R_SC_W --> R_SC_R
        end
        RAW_C --> R_SC_C
        RAW_W --> R_SC_W
        RAW_R --> R_SC_R
    end

    DEPLOY --> RAW_C
    WRITE  --> RAW_W
    READ   --> RAW_R
    ADMIN  ==> RAW_DB

    subgraph SNOW_D_INT["SNOW_D_INT — Integration Zone"]
        INT_DB[("SNOW_D_INT")]
        INT_C["DB_C"]
        INT_W["DB_W"]
        INT_R["DB_R"]
        subgraph SC_INT_TPCH["Schema: TPCH"]
            I_SC_C["SC_C_TPCH<br/>DDL"]
            I_SC_W["SC_W_TPCH<br/>DML"]
            I_SC_R["SC_R_TPCH<br/>SELECT"]
            I_SC_C --> I_SC_W --> I_SC_R
        end
        INT_C --> I_SC_C
        INT_W --> I_SC_W
        INT_R --> I_SC_R
    end

    DEPLOY --> INT_C
    WRITE  --> INT_W
    READ   --> INT_R
    ADMIN  ==> INT_DB

    subgraph SNOW_D_PRES["SNOW_D_PRES — Presentation Zone"]
        PRE_DB[("SNOW_D_PRES")]
        PRE_C["DB_C"]
        PRE_W["DB_W"]
        PRE_R["DB_R"]
        subgraph SC_PRES_SALES["Schema: SALES"]
            P_SC_C["SC_C_SALES<br/>DDL"]
            P_SC_W["SC_W_SALES<br/>DML"]
            P_SC_R["SC_R_SALES<br/>SELECT"]
            P_SC_C --> P_SC_W --> P_SC_R
        end
        PRE_C --> P_SC_C
        PRE_W --> P_SC_W
        PRE_R --> P_SC_R
    end

    DEPLOY --> PRE_C
    WRITE  --> PRE_W
    READ   --> PRE_R
    ADMIN  ==> PRE_DB

    subgraph LEGEND["Legend"]
        L1["thin arrow  =  role inherited"]
        L2["thick arrow  =  ownership"]
        L3["dashed arrow  =  privilege grant on object"]
    end
```
