# Simple general-purpose queue.

type EmptyQueue <: Exception
end

type UnderfullQueue <: Exception
end

type QueueNode{T}
    value::T
    next::Union{QueueNode, Void}
end


type Queue{T}
    front::Union{QueueNode{T}, Void}
    back::Union{QueueNode{T}, Void}
    length::UInt64

    function (::Type{Queue{T}}){T}()
        new{T}(nothing, nothing, 0)
    end
end

isempty(q::Queue) = length(q.data) == 0
length(q::Queue) = length(q.data)
peek(q::Queue) = q.data[1]
enqueue!{T}(q::Queue{T}, value::T) = push!(q.data, value)
# Enqueue into kth place.
enqueue!{T}(q::Queue{T}, value::T, k::Integer) = insert!(q.data, k+1, value)
dequeue!(q::Queue) = shift!(q.data)

