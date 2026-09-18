### Overrides
###
### Merging given entries onto defaults, used by the plot styles and the script configurations
###         - 1) Merging
###         - 2) Printing










### 1) Merging

# Merge given entries onto the defaults, an entry the defaults do not know is a typo
#
# Example:
#     checked_merge((; width = 32, act = tanh), (; width = 64))   ->  (; width = 64, act = tanh)
#     checked_merge((; width = 32, act = tanh), (; widht = 64))   ->  error
function checked_merge(defaults, given)

    # Entries of given, which are unknown (not in the defaults)
    unknown = setdiff(keys(given), keys(defaults))

    # Throw an error if there are unknown entries
    isempty(unknown) || error("Unknown entries $(Tuple(unknown)), allowed: $(keys(defaults))")

    # Merge defaults and given entries (given has priority)
    return merge(defaults, given)
end










### 2) Printing

# Print the merged configuration c of a script unit u, marking every value the unit set itself
function print_unit_config(config, unit; title = "Unit configuration")

    # Longest key name, for aligning the values
    pad = maximum(length(string(k)) for k in keys(config))

    # Print one line per key
    println("---------- ", title, " ----------")
    for k in keys(config)
        println("  ", haskey(unit, k) ? "*" : " ", " ", rpad(string(k), pad), " = ", short_string(config[k]))
    end
    println("  (* = set by the unit, everything else from the defaults)")
    println("-"^(22 + length(title)))

    return nothing
end



# Compact representation of one configuration value (cut after 70 characters)
short_string(v) = (s = string(v); length(s) > 70 ? first(s, 67) * "..." : s)
