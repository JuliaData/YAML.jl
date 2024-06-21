Dict("process" => Dict("sigma" => 0.1, :tag => :AR1, "rho" =>0.95),
     "grid" => Dict("orders" => [10, 50], "b" => ["1+2*sig_z", "k*1.1"], "a" => ["1-2*sig_z", "k*0.9"], "mu" => 3, :tag => :Cartesian))
