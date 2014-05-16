;;;;;
;;;;;
;;;;;
(require marx.language)


(defmacro wheatley-spawn [&rest args]
  `(go (wheatley-simple-launch docker [~@args])))


(defmacro wheatley [&rest forms] `(marx ~@forms))
