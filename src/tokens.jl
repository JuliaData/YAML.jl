
# YAML Tokens.
# Each token must include at minimum member "span::Span".
abstract Token


# The '%YAML' directive.
type DirectiveToken <: Token
    span::Span
    name::String
    value::Union(String, Nothing)
end

# '---'
type DocumentStartToken <: Token
    span::Span
end

# '...'
type DocumentEndToken <: Token
    span::Span
end

# The stream start
type StreamStartToken <: Token
    span::Span
    encoding::String
end

# The stream end
type StreamEndToken <: Token
    span::Span
end

#
type BlockSequenceStartToken <: Token
    span::Span
end

#
type BlockMappingStartToken <: Token
    span::Span
end

#
type BlockEndToken <: Token
    span::Span
end

# '['
type FlowSequenceStartToken <: Token
    span::Span
end

# '{'
type FlowMappingStartToken <: Token
    span::Span
end

# ']'
type FlowSequenceEndToken <: Token
    span::Span
end

# '}'
type FlowMappingEndToken <: Token
    span::Span
end

# '?' or nothing (simple keys).
type KeyToken <: Token
    span::Span
end

# ':'
type ValueToken <: Token
    span::Span
end

# '-'
type BlockEntryToken <: Token
    span::Span
end

# ','
type FlowEntryToken <: Token
    span::Span
end

# '*anchor'
type AliasToken <: Token
    span::Span
    value::String
end

# '&anchor'
type AnchorToken <: Token
    span::Span
    value::String
end

# '!handle!suffix'
type TagToken <: Token
    span::Span
    value
end

# A scalar.
type ScalarToken <: Token
    span::Span
    value::String
    plain::Bool
    style::Union(Char, Nothing)
end


