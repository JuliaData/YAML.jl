# Constructors for the Core schema.

construct_undefined_core_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the Core schema", node.start_mark))

const construct_core_schema_str = construct_failsafe_schema_str

const construct_core_schema_seq = construct_failsafe_schema_seq

const construct_core_schema_map = construct_failsafe_schema_map

const core_schema_null_values = Dict(
    "null" => nothing,
    "Null" => nothing,
    "NULL" => nothing,
    "~"    => nothing,
)

function construct_core_schema_null(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    core_schema_null_values[value]
end

const core_schema_bool_values = Dict(
    "true"  => true,
    "True"  => true,
    "TRUE"  => true,
    "false" => false,
    "False" => false,
    "FALSE" => false,
)

function construct_core_schema_bool(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    core_schema_bool_values[value]
end

function construct_core_schema_int(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
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

function construct_core_schema_float(construct::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    # not a number
    value == ".nan" && return NaN
    # infinity
    m = match(r"^([+\-]?)\.inf$", value)
    if m !== nothing
        if m.captures[1] == "-"
            return -Inf
        else
            return Inf
        end
    end
    # fixed or exponential
    parse(Float64, value)
end

const core_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                   => construct_undefined_core_schema,
    "tag:yaml.org,2002:str"   => construct_core_schema_str,
    "tag:yaml.org,2002:seq"   => construct_core_schema_seq,
    "tag:yaml.org,2002:map"   => construct_core_schema_map,
    "tag:yaml.org,2002:null"  => construct_core_schema_null,
    "tag:yaml.org,2002:bool"  => construct_core_schema_bool,
    "tag:yaml.org,2002:int"   => construct_core_schema_int,
    "tag:yaml.org,2002:float" => construct_core_schema_float,
)
