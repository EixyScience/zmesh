go run .\cmd\zmesh agent -c .\zmesh.conf



# routerの場合分け
# productionなら
# writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
# developmentなら
# writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json: " + err.Error()})

