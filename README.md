### Admin commands

| command            | shortform | arguments        | description                    |
|--------------------|-----------|------------------|--------------------------------|
| sm_setteam         | sm_st     | `client` `team`  |Set the targets team            |
| sm_setclass        | sm_sc     | `client` `class` |Set the target class            |
| sm_ready           | sm_rdy    | `team` `0/1`     |Set a team's ready status       |
| sm_debug_roundtime | sm_drt    | -                |Print the team_round_timer info |

### Backup admin commands

| command            | shortform | arguments | description                         |
|--------------------|-----------|-----------|-------------------------------------|
| sm_enable_resupply | sm_res    | `0/1`     |Enable resupply functionality        |
| sm_enable_respawn  | sm_resp   | `0/1`     |Enable instant respawn               |
| sm_enable_immunity | sm_imm    | `0/1`     |Enable immunity and infinite ammo    |
| sm_enable_saveload | sm_sl     | `0/1`     |Enable save/load spawn functionality |
| sm_plugin_status   | sm_ps     | -         |Show current plugin feature status   |

### Client commands

| command         | shortform | arguments | description                        |
|-----------------|-----------|-----------|------------------------------------|
| sm_save         | sm_sv     | -         | Save a spawn point                 |
| sm_load         | sm_ld     | -         | Teleport to saved spawn            |
| sm_immune       | sm_i      | -         | Toggle invulnerability             |
| sm_ammo         | sm_a      | -         | Toggle infinite ammo               |
| sm_fov          | -         | `70-120`  | Set your field of view             |
| +sm_resupply    | -         | -         | Instant resupply when inside spawn |
| +sm_pt_resupply | -         | -         | Instant resupply when inside spawn |