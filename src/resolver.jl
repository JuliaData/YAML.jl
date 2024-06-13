const Resolution = Pair{String, Regex}

struct Resolver
    default_scalar_tag::String
    default_sequence_tag::String
    default_mapping_tag::String
    # `Dict{String, Regex}` might be better for resolutions.
    # However, dicts are unordered so it changes the current behavior of `resolve`.
    scalar_resolutions::Vector{Resolution}
    sequence_resolutions::Vector{Resolution}
    mapping_resolutions::Vector{Resolution}
end

# The resolver for the failsafe schema.
const FAILSAFE_SCHEMA_RESOLVER = Resolver(
    "tag:yaml.org,2002:str",
    "tag:yaml.org,2002:seq",
    "tag:yaml.org,2002:map",
    [],
    [],
    [],
)

# The resolver for the JSON schema.
const JSON_SCHEMA_RESOLVER = Resolver(
    "tag:yaml.org,2002:str",
    "tag:yaml.org,2002:seq",
    "tag:yaml.org,2002:map",
    [
        "tag:yaml.org,2002:null" => r"^(?: null )$"x,
        "tag:yaml.org,2002:bool" => r"^(?: true | false )$"x,
        "tag:yaml.org,2002:int" => r"^(?: -? ( 0 | [1-9] [0-9]* ) )$"x,
        "tag:yaml.org,2002:float" => r"^(?:
            -? ( 0 | [1-9] [0-9]* )
            ( \. [0-9]* )?
            ( [eE] [-+]? [0-9]+ )?
        )$"x,
    ],
    [],
    [],
)

# The resolver for the Core schema.
const CORE_SCHEMA_RESOLVER = Resolver(
    "tag:yaml.org,2002:str",
    "tag:yaml.org,2002:seq",
    "tag:yaml.org,2002:map",
    [
        "tag:yaml.org,2002:null" => r"^(?: null | Null | NULL | ~ |  )$"x,
        "tag:yaml.org,2002:bool" => r"^(?: true | True | TRUE | false | False | FALSE )$"x,
        "tag:yaml.org,2002:int" => r"^(?:
            [-+]? [0-9]+ |
            0o [0-7]+ |
            0x [0-9a-fA-F]+
        )$"x,
        "tag:yaml.org,2002:float" => r"^(?:
            [-+]? ( \. [0-9]+ | [0-9]+ ( \. [0-9]* )? ) ( [eE] [-+]? [0-9]+ )? |
            [-+]? ( \.inf | \.Inf | \.INF ) |
            \.nan | \.NaN | \.NAN
        )$"x,
    ],
    [],
    [],
)

# The resolver for the YAML.jl v0.4.10 schema.
const YAML_JL_0_4_10_RESOLVER = Resolver(
    "tag:yaml.org,2002:str",
    "tag:yaml.org,2002:seq",
    "tag:yaml.org,2002:map",
    [
        "tag:yaml.org,2002:bool" => r"^(?:true|True|TRUE|false|False|FALSE)$"x,
        "tag:yaml.org,2002:int" => r"^(?:
            [-+]?0b[0-1_]+ |
            [-+]? [0-9]+ |
            0o [0-7]+ |
            0x [0-9a-fA-F]+
        )$"x,
        "tag:yaml.org,2002:float" => r"^(?:
            [-+]? ( \. [0-9]+ | [0-9]+ ( \. [0-9]* )? ) ( [eE] [-+]? [0-9]+ )? |
            [-+]? (?: \.inf | \.Inf | \.INF ) |
            \.nan | \.NaN | \.NAN
        )$"x,
        "tag:yaml.org,2002:merge" => r"^(?:<<)$",
        "tag:yaml.org,2002:null" => r"^(?:~|null|Null|NULL|)$"x,
        "tag:yaml.org,2002:timestamp" => r"^
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
                    [ \t]*(Z|([+\-])(\d\d?)
                        (?:
                            :(\d\d)
                        )?
                    )
                )?
            )?
        $"x,
        "tag:yaml.org,2002:value" => r"^(?:=)$",
        "tag:yaml.org,2002:yaml" => r"^(?:!|&|\*)$",
    ],
    [],
    [],
)

Resolver() = YAML_JL_0_4_10_RESOLVER

function resolve(resolver::Resolver, ::Type{ScalarNode}, value, implicit)
    if implicit[1]
        for (tag, pat) in resolver.scalar_resolutions
            if occursin(pat, value)
                return tag
            end
        end
    end
    resolver.default_scalar_tag
end

function resolve(resolver::Resolver, ::Type{SequenceNode}, value, implicit)
    if implicit[1]
        for (tag, pat) in resolver.sequence_resolutions
            if occursin(pat, value)
                return tag
            end
        end
    end
    resolver.default_sequence_tag
end

function resolve(resolver::Resolver, ::Type{MappingNode}, value, implicit)
    if implicit[1]
        for (tag, pat) in resolver.mapping_resolutions
            if occursin(pat, value)
                return tag
            end
        end
    end
    resolver.default_mapping_tag
end
