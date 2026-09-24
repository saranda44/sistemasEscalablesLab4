-- wrk2 script: POST /cached with a random item id in the body.
-- Run with e.g.:
--   wrk -t4 -c50 -d30s -R500 --latency -s benchmark/cached.lua http://<alb-dns>/cached

wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"

math.randomseed(os.time())

request = function()
  local id = math.random(1, 200)
  local body = string.format('{"id": %d}', id)
  return wrk.format(nil, nil, nil, body)
end
