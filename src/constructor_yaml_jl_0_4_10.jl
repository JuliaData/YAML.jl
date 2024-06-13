# Constructors for the YAML.jl v0.4.10 schema.

construct_undefined_yaml_jl_0_4_10_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' the YAML.jl v0.4.0 schema", node.start_mark))

construct_yaml_jl_0_4_10_schema_str(constructor::Constructor, node::Node) =
    string(construct_scalar(constructor, node))

construct_yaml_jl_0_4_10_schema_seq(constructor::Constructor, node::Node) =
    construct_sequence(constructor, node)

construct_yaml_jl_0_4_10_schema_map(constructor::Constructor, node::Node) =
    construct_mapping(constructor, node)

function construct_yaml_jl_0_4_10_schema_null(constructor::Constructor, node::Node)
    _ = construct_scalar(constructor, node)
    nothing
end

# TODO: There is no resolver definition of
# - yes
# - no
# - on
# - off
# in resolver.jl. It's strange. Why do they exist here?
const yaml_jl_0_4_10_schema_bool_values = Dict(
    "yes"   => true,
    "no"    => false,
    "true"  => true,
    "false" => false,
    "on"    => true,
    "off"   => false,
)

function construct_yaml_jl_0_4_10_schema_bool(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    yaml_jl_0_4_10_schema_bool_values[lowercase(value)]
end

function construct_yaml_jl_0_4_10_schema_int(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    value = lowercase(replace(value, "_" => ""))

    # sexagesimal integers
    if in(':', value)
        # TODO:
        # throw(ConstructorError("sexagesimal integers not yet implemented", node.start_mark))
        @warn "sexagesimal integers not yet implemented. Returning String."
        return value
    end

    # hexadecimal
    if length(value) > 2 && value[1] == '0' && (value[2] == 'x' || value[2] == 'X')
        parse(Int, value[3:end], base=16)
    # octal
    elseif length(value) > 1 && value[1] == '0'
        parse(Int, value, base=8)
    # decimal
    else
        parse(Int, value, base=10)
    end
end

function construct_yaml_jl_0_4_10_schema_float(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    value = lowercase(replace(value, "_" => ""))

    # sexagesimal float
    if in(':', value)
        # TODO:
        # throw(ConstructorError("sexagesimal floats not yet implemented", node.start_mark))
        @warn "sexagesimal floats not yet implemented. Returning String."
        return value
    end

    # not a number
    value == ".nan" && return NaN

    # infinity
    m = match(r"^([+\-]?)\.inf$", value)
    if m !== nothing
        # negative infinity
        if m.captures[1] == "-"
            return -Inf
        # positive infinity
        else
            return Inf
        end
    end

    # fixed or exponential
    parse(Float64, value)
end

const timestamp_pat = r"^
    (\d{4})- (?# year)
    (\d\d?)- (?# month)
    (\d\d?)  (?# day)
    (?:
        (?:[Tt]|[ \t]+)
        (\d\d?):     (?# hour)
        (\d\d):      (?# minute)
        (\d\d)       (?# second)
        (?:\.(\d*))? (?# fraction)
        (?:
            [ \t]*(
                Z |
                (?:[+\-])(\d\d?)
                (?:
                    :(\d\d)
                )?
            )
        )?
    )?
$"x

function construct_yaml_jl_0_4_10_schema_timestamp(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    mat = match(timestamp_pat, value)
    mat === nothing && throw(ConstructorError("could not make sense of timestamp format", node.start_mark))

    yr = parse(Int, mat.captures[1])
    mn = parse(Int, mat.captures[2])
    dy = parse(Int, mat.captures[3])
    mat.captures[4] === nothing && return Date(yr, mn, dy)

    h = parse(Int, mat.captures[4])
    m = parse(Int, mat.captures[5])
    s = parse(Int, mat.captures[6])
    mat.captures[7] === nothing && return DateTime(yr, mn, dy, h, m, s)

    ms = 0
    if mat.captures[7] !== nothing
        ms = mat.captures[7]
        if length(ms) > 3
            ms = ms[1:3]
        end
        ms = parse(Int, string(ms, repeat("0", 3 - length(ms))))
    end

    delta_hr = 0
    delta_mn = 0

    if mat.captures[9] !== nothing
        delta_hr = parse(Int, mat.captures[9])
    end

    if mat.captures[10] !== nothing
        delta_mn = parse(Int, mat.captures[10])
    end

    # TODO: Also, I'm not sure if there is a way to numerically set the timezone
    # in Calendar.

    DateTime(yr, mn, dy, h, m, s, ms)
end

construct_yaml_jl_0_4_10_schema_omap(constructor::Constructor, node::Node) =
    throw(ConstructorError("omap type not yet implemented", node.start_mark))

construct_yaml_jl_0_4_10_schema_pairs(constructor::Constructor, node::Node) =
    throw(ConstructorError("pairs type not yet implemented", node.start_mark))

construct_yaml_jl_0_4_10_schema_set(constructor::Constructor, node::Node) =
    throw(ConstructorError("set type not yet implemented", node.start_mark))

construct_yaml_jl_0_4_10_schema_object(constructor::Constructor, node::Node) =
    throw(ConstructorError("object type not yet implemented", node.start_mark))

function construct_yaml_jl_0_4_10_schema_binary(constructor::Constructor, node::Node)
    value = replace(string(construct_scalar(constructor, node)), "\n" => "")
    base64decode(value)
end

const yaml_jl_0_4_10_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                       => construct_undefined_yaml_jl_0_4_10_schema,
    "tag:yaml.org,2002:str"       => construct_yaml_jl_0_4_10_schema_str,
    "tag:yaml.org,2002:seq"       => construct_yaml_jl_0_4_10_schema_seq,
    "tag:yaml.org,2002:map"       => construct_yaml_jl_0_4_10_schema_map,
    "tag:yaml.org,2002:null"      => construct_yaml_jl_0_4_10_schema_null,
    "tag:yaml.org,2002:bool"      => construct_yaml_jl_0_4_10_schema_bool,
    "tag:yaml.org,2002:int"       => construct_yaml_jl_0_4_10_schema_int,
    "tag:yaml.org,2002:float"     => construct_yaml_jl_0_4_10_schema_float,
    "tag:yaml.org,2002:binary"    => construct_yaml_jl_0_4_10_schema_binary,
    "tag:yaml.org,2002:timestamp" => construct_yaml_jl_0_4_10_schema_timestamp,
    "tag:yaml.org,2002:omap"      => construct_yaml_jl_0_4_10_schema_omap,
    "tag:yaml.org,2002:pairs"     => construct_yaml_jl_0_4_10_schema_pairs,
    "tag:yaml.org,2002:set"       => construct_yaml_jl_0_4_10_schema_set,
    # TODO: Investigate how these 3 tags are processed in the YAML.jl v0.4.10 schema.
    # "tag:yaml.org,2002:merge"
    # "tag:yaml.org,2002:value"
    # "tag:yaml.org,2002:yaml"
)
