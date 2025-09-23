# passtime.tf extras

## Dependencies

- [TF2 Attributes](https://github.com/FlaminSarge/tf2attributes) by FlaminSarge

## Commands

### Admin

| command            | shortform | arguments            | description                                 |
|--------------------|-----------|----------------------|---------------------------------------------|
| sm_setteam         | sm_st     | `client` `team`      | Set the target's team                       |
| sm_setclass        | sm_sc     | `client` `class`     | Set the target's class                      |
| sm_ready           | sm_rdy    | `team` `0/1`         | Set a team's ready status                   |
| sm_debug_roundtime | sm_drt    | -                    | Print the team_round_timer info             |
| sm_debug_classes   | sm_dbc    | `client`             | Print the target's class info               |
| sm_checkatt        | sm_ca     | `ent_id` `prop_name` | Check if an entity has a specific attribute |

### Backup admin

| command            | arguments | description                          |
|--------------------|-----------|--------------------------------------|
| sm_enable_resupply | `0/1`     | Enable resupply functionality        |
| sm_enable_respawn  | `0/1`     | Enable instant respawn               |
| sm_enable_immunity | `0/1`     | Enable immunity and infinite ammo    |
| sm_enable_saveload | `0/1`     | Enable save/load spawn functionality |
| sm_enable_demovuln | `0/1`     | Enable demo blast vulnerability      |

### Client

| command         | shortform | arguments                                                                 | description                                                |
|-----------------|-----------|---------------------------------------------------------------------------|------------------------------------------------------------|
| sm_save         | sm_sv     | -                                                                         | Save a spawn point                                         |
| sm_load         | sm_ld     | -                                                                         | Teleport to saved spawn                                    |
| sm_immune       | sm_i      | -                                                                         | Toggle invulnerability                                     |
| sm_ammo         | sm_a      | -                                                                         | Toggle infinite ammo                                       |
| sm_diceroll     | sm_dice   | `client1` `client2` `...` OR `@all/red/blue` OR `"word1"` `"word2"` `...` | Select a random player from targets                        |
| sm_fov          | -         | `70-120`                                                                  | Set your field of view                                     |
| +sm_resupply    | -         | -                                                                         | Instant resupply when inside spawn                         |
| +sm_pt_resupply | -         | -                                                                         | Instant resupply when inside spawn                         |

### Server console variables

| command         | default | description                     |
|-----------------|---------|---------------------------------|
| sm_fov_min      | `70`    | Minimum client field of view    |
| sm_fov_max      | `120`   | Maximum client field of view    |
| sm_respawn_time | `0.0`   | Player respawn delay in seconds |
