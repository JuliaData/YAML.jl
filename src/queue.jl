
# Simple general-purpose queue.

type EmptyQueue <: Exception
end

type UnderfullQueue <: Exception
end

type QueueNode{T}
    value::T
    next::Union(QueueNode, Nothing)
end


type Queue{T}
    front::Union(QueueNode{T}, Nothing)
    back::Union(QueueNode{T}, Nothing)
    length::Uint

    function Queue()
        new(nothing, nothing, 0)
    end
end


isempty(q::Queue) = q.front === nothing
length(q::Queue) = q.length


function enqueue!{T}(q::Queue{T}, value)
    newback = QueueNode{T}(convert(T, value), nothing)
    if q.back === nothing
        q.front = q.back = newback
    else
        q.back.next = newback
        q.back = newback
    end
    q.length += 1
    q.back.value
end


# Enqueue into kth place.
function enqueue!{T}(q::Queue{T}, value, k)
    newnode = QueueNode{T}(convert(T, value), nothing)
    if k == 0
        newnode.next = q.front
        q.front = newnode
    elseif k > q.length
        throw(UnderfullQueue())
    else
        front = q.front
        for _ in 1:(k-1)
            front = front.next
        end
        newnode = front.next
        front.next = newnode
    end
    if newnode.next === nothing
        q.back = newnode
    end
    q.length += 1
    newnode.value
end


function dequeue!(q::Queue)
    if q.front === nothing
        throw(EmptyQueue())
    else
        value = q.front.value
        q.front = q.front.next
        if q.front === nothing
            q.back = nothing
        end
        q.length -= 1
        value
    end
end


function peek(q::Queue)
    if q.front === nothing
        throw(EmptyQueue())
    else
        return q.front.value
    end
end


