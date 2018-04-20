mutable struct Queue{T}
    data::Vector{T}
    function (::Type{Queue{T}})() where T
        new{T}(Vector{T}())
    end
end

isempty(q::Queue) = length(q.data) == 0
length(q::Queue) = length(q.data)
peek(q::Queue) = q.data[1]
enqueue!(q::Queue{T}, value::T) where T = push!(q.data, value)
# Enqueue into kth place.
enqueue!(q::Queue{T}, value::T, k::Integer) where T = insert!(q.data, k+1, value)
dequeue!(q::Queue) = popfirst!(q.data)
