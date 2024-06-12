

# TODO:
# This is a punt for now. It does not handle any sort of custom resolving tags,
# only matching default implicits.


const DEFAULT_SCALAR_TAG = "tag:yaml.org,2002:str"
const DEFAULT_SEQUENCE_TAG = "tag:yaml.org,2002:seq"
const DEFAULT_MAPPING_TAG = "tag:yaml.org,2002:map"


const default_implicit_resolvers =
    [
         ("tag:yaml.org,2002:bool",
          r"^(?:true|True|TRUE|false|False|FALSE)$"x),

         ("tag:yaml.org,2002:int",
          r"^(?:[-+]?0b[0-1_]+
            |[-+]? [0-9]+
            |0o [0-7]+
            |0x [0-9a-fA-F]+)$"x),

         ("tag:yaml.org,2002:float",
          r"^(?:[-+]? ( \. [0-9]+ | [0-9]+ ( \. [0-9]* )? ) ( [eE] [-+]? [0-9]+ )?
            |[-+]? (?: \.inf | \.Inf | \.INF )
            |\.nan | \.NaN | \.NAN)$"x),

         ("tag:yaml.org,2002:merge",
          r"^(?:<<)$"),

         ("tag:yaml.org,2002:null",
          r"^(?:~|null|Null|NULL|)$"x),

         ("tag:yaml.org,2002:timestamp",
          r"^(\d{4})-    (?# year)
             (\d\d?)-    (?# month)
             (\d\d?)     (?# day)
            (?:
              (?:[Tt]|[ \t]+)
              (\d\d?):      (?# hour)
              (\d\d):       (?# minute)
              (\d\d)        (?# second)
              (?:\.(\d*))?  (?# fraction)
              (?:
                [ \t]*(Z|([+\-])(\d\d?)
                  (?:
                      :(\d\d)
                  )?)
              )?
            )?$"x),

         ("tag:yaml.org,2002:value",
          r"^(?:=)$"),

         ("tag:yaml.org,2002:yaml",
          r"^(?:!|&|\*)$")
    ]


struct Resolver
    implicit_resolvers::Vector{Tuple{String,Regex}}

    function Resolver()
        new(copy(default_implicit_resolvers))
    end
end


function resolve(resolver::Resolver, ::Type{ScalarNode}, value, implicit)
    if implicit[1]
        for (tag, pat) in resolver.implicit_resolvers
            if occursin(pat, value)
                return tag
            end
        end
    end

    DEFAULT_SCALAR_TAG
end


function resolve(resolver::Resolver, ::Type{SequenceNode}, value, implicit)
    DEFAULT_SEQUENCE_TAG
end

function resolve(resolver::Resolver, ::Type{MappingNode}, value, implicit)
    DEFAULT_MAPPING_TAG
end

