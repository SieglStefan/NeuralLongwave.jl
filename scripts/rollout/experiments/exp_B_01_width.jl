### NLW seeding experiment
###
### Questions:
###     - Are other architectures better at learning the NLW scheme than the default MLP architecture?



# Define experiment name
EXP = "exp_B_01_width"



# Define parameters for the experiment
REF     = "OBLW_default"
SKILL   = (; max_horizon = 31,  n_traj = 52, heatmap_days = [1, 3, 7, 14, 31])
STAB    = (; max_horizon = 365, n_traj = 4,  heatmap_days = [30, 90, 180, 365])   



# Define experiments
experiments = [
    
    ### OneBandLongwave (sanity test, should lead to zero rmse, bias,...)
    # 0. Skill
    (;  name            = "OBLW_skill",
        scheme          = :OBLW,
        reference       = REF,
        SKILL...
    ),
    # 1. Stability
    (;  name            = "OBLW_stab",
        scheme          = :OBLW,
        reference       = REF,
        STAB...
    ),



    ### MLP, n_hidden=2, width=32, seed = 1000
    # 2. Skill
    (;  name            = "MLP_s1000_skill",
        scheme          = "MLP_s1000",
        reference       = REF,
        SKILL...
    ),
    # 3. Stability
    (;  name            = "MLP_s1000_stab",
        scheme          = "MLP_s1000",
        reference       = REF,
        STAB...
    ),



    ### width = 8, seed = 1000
    # 4. Skill
    (;  name            = "RNN_w8_s1000_skill",
        scheme          = "RNN_w8_s1000",
        reference       = REF,
        SKILL...
    ),
    # 5. Stability
    (;  name            = "RNN_w8_s1000_stab",
        scheme          = "RNN_w8_s1000",
        reference       = REF,
        STAB...
    ),

    ### width = 16, seed = 1000
    # 6. Skill
    (;  name            = "RNN_w16_s1000_skill",
        scheme          = "RNN_w16_s1000",
        reference       = REF,
        SKILL...
    ),
    # 7. Stability
    (;  name            = "RNN_w16_s1000_stab",
        scheme          = "RNN_w16_s1000",
        reference       = REF,
        STAB...
    ),

    ### width = 32, seed = 1000
    # 8. Skill
    (;  name            = "RNN_w32_s1000_skill",
        scheme          = "RNN_w32_s1000",
        reference       = REF,
        SKILL...
    ),
    # 9. Stability
    (;  name            = "RNN_w32_s1000_stab",
        scheme          = "RNN_w32_s1000",
        reference       = REF,
        STAB...
    ),

    ### width = 64, seed = 1000
    # 10. Skill
    (;  name            = "RNN_w64_s1000_skill",
        scheme          = "RNN_w64_s1000",
        reference       = REF,
        SKILL...
    ),
    # 11. Stability
    (;  name            = "RNN_w64_s1000_stab",
        scheme          = "RNN_w64_s1000",
        reference       = REF,
        STAB...
    ),

    ### width = 128, seed = 1000
    # 12. Skill
    (;  name            = "RNN_w128_s1000_skill",
        scheme          = "RNN_w128_s1000",
        reference       = REF,
        SKILL...
    ),
    # 13. Stability
    (;  name            = "RNN_w128_s1000_stab",
        scheme          = "RNN_w128_s1000",
        reference       = REF,
        STAB...
    ),



    ### MLP, n_hidden=2, width=32, seed = 2000
    # 14. Skill
    (;  name            = "MLP_s2000_skill",
        scheme          = "MLP_s2000",
        reference       = REF,
        SKILL...
    ),
    # 15. Stability
    (;  name            = "MLP_s2000_stab",
        scheme          = "MLP_s2000",
        reference       = REF,
        STAB...
    ),



    ### width = 8, seed = 2000
    # 16. Skill
    (;  name            = "RNN_w8_s2000_skill",
        scheme          = "RNN_w8_s2000",
        reference       = REF,
        SKILL...
    ),
    # 17. Stability
    (;  name            = "RNN_w8_s2000_stab",
        scheme          = "RNN_w8_s2000",
        reference       = REF,
        STAB...
    ),

    ### width = 16, seed = 2000
    # 18. Skill
    (;  name            = "RNN_w16_s2000_skill",
        scheme          = "RNN_w16_s2000",
        reference       = REF,
        SKILL...
    ),
    # 19. Stability
    (;  name            = "RNN_w16_s2000_stab",
        scheme          = "RNN_w16_s2000",
        reference       = REF,
        STAB...
    ),

    ### width = 32, seed = 2000
    # 20. Skill
    (;  name            = "RNN_w32_s2000_skill",
        scheme          = "RNN_w32_s2000",
        reference       = REF,
        SKILL...
    ),
    # 21. Stability
    (;  name            = "RNN_w32_s2000_stab",
        scheme          = "RNN_w32_s2000",
        reference       = REF,
        STAB...
    ),

    ### width = 64, seed = 2000
    # 22. Skill
    (;  name            = "RNN_w64_s2000_skill",
        scheme          = "RNN_w64_s2000",
        reference       = REF,
        SKILL...
    ),
    # 23. Stability
    (;  name            = "RNN_w64_s2000_stab",
        scheme          = "RNN_w64_s2000",
        reference       = REF,
        STAB...
    ),

    ### width = 128, seed = 2000
    # 24. Skill
    (;  name            = "RNN_w128_s2000_skill",
        scheme          = "RNN_w128_s2000",
        reference       = REF,
        SKILL...
    ),
    # 25. Stability
    (;  name            = "RNN_w128_s2000_stab",
        scheme          = "RNN_w128_s2000",
        reference       = REF,
        STAB...
    ),
]
