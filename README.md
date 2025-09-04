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

### Console variables for the server

| command         | default | description                     |
|-----------------|---------|---------------------------------|
| sm_fov_min      | `70`    | Minimum client field of view    |
| sm_fov_max      | `120`   | Maximum client field of view    |
| sm_respawn_time | `0.0`   | Player respawn delay in seconds |