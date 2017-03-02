
# YAML Tokens.
# Each token must include at minimum member "span::Span".
@compat abstract type Token end


# The '%YAML' directive.
immutable DirectiveToken <: Token
    span::Span
    name::AbstractString
    value::Union{Tuple, Void}
end

# '---'
immutable DocumentStartToken <: Token
    span::Span
end

# '...'
immutable DocumentEndToken <: Token
    span::Span
end

# The stream start
immutable StreamStartToken <: Token
    span::Span
    encoding::AbstractString
end

# The stream end
immutable StreamEndToken <: Token
    span::Span
end

#
immutable BlockSequenceStartToken <: Token
    span::Span
end

#
immutable BlockMappingStartToken <: Token
    span::Span
end

#
immutable BlockEndToken <: Token
    span::Span
end

# '['
immutable FlowSequenceStartToken <: Token
    span::Span
end

# '{'
immutable FlowMappingStartToken <: Token
    span::Span
end

# ']'
immutable FlowSequenceEndToken <: Token
    span::Span
end

# '}'
immutable FlowMappingEndToken <: Token
    span::Span
end

# '?' or nothing (simple keys).
immutable KeyToken <: Token
    span::Span
end

# ':'
immutable ValueToken <: Token
    span::Span
end

# '-'
immutable BlockEntryToken <: Token
    span::Span
end

# ','
immutable FlowEntryToken <: Token
    span::Span
end

# '*anchor'
immutable AliasToken <: Token
    span::Span
    value::AbstractString
end

# '&anchor'
immutable AnchorToken <: Token
    span::Span
    value::AbstractString
end

# '!handle!suffix'
immutable TagToken <: Token
    span::Span
    value
end

# A scalar.
immutable ScalarToken <: Token
    span::Span
    value::AbstractString
    plain::Bool
    style::Union{Char, Void}
end
