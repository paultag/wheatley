(require marx.language)
(import asyncio [wheatley.kwzip [group-map keyword? one]])


(defmacro disown [&rest forms]
  `(.async asyncio ((fn/coroutine [] ~@forms))))


(defmacro wheatley-debug [&rest forms]
  `(print ~@forms))


(defmacro broadcast [class name event container]
  (define [[ename (gensym)]]
    `(define [[~ename {"class" ~class
                       "name" ~name
                       "id" container._id
                       "event" ~event
                       "container" ~container}]]
      (emit :wheatley ~ename)
      (emit (+ :wheatley "-" ~class) ~ename)
      (emit (+ :wheatley "-" ~class "-" ~event) ~ename)

      (if (is-not ~name nil)
        (do
          (emit (+ :wheatley "-" ~name) ~ename)
          (emit (+ :wheatley "-" ~class "-" ~name) ~ename)
          (emit (+ :wheatley "-" ~class "-" ~name "-" ~event) ~ename))))))


(defn wheatley-run [data]
  "Central run code"
  (defn parse-string [input]
      ;; "172.17.42.1:53:53/udp"
      (let [[(, host hport) (.rsplit input ":" 1)]
            [(, ip cport) (.rsplit host ":" 1)]
            [hport (HyString hport)]
            [ip (HyString ip)]
            [cport (HyString cport)]]
        `{~hport [{"HostIp" ~ip "HostPort" ~cport}]}))

  (defn parse-strings [inputs]
    (setv concrete `{})
    (for [input inputs]
      (setv concrete (+ concrete (parse-string input))))
    (setv bindings `{"PortBindings" ~concrete})
    bindings)

  (define [[binds (list-comp (HyString (.join ":" x)) [x (:volumes data)])]
           [links (list-comp (HyString (.join ":" x)) [x (:links data)])]
           [iname (gensym)]
           [privileged (one 'false (:privileged data))]
           [config `{"Binds" [~@binds]
                     "Privileged" ~privileged
                     "Links" [~@links]}]]

    (if (.get data :port-mapping)
      (setv config (+ config (parse-strings (:port-mapping data)))))

    `(do
      (go-setv ~iname (.show container))
      (if (is (-> ~iname (get "State") (get "Running")) false)
        (go (.start container ~config))))))


(defn wheatley-depwait [data]
  (define [[deps (:requires data)]]
    `(go (apply asyncio.gather
      (list-comp
        ((fn/coroutine [name]

          ; before we go any further, let's see if it's running.

          (setv running false)
          (try
            (define [[container (go (.get docker.containers name))]
                     [info (. container _container)]
                     [running (-> info (get "State") (get "Running"))]])
          (except [ValueError]))

          (if (not running)
            (define [[queue (.listen docker.events)]]
              (print (% " => dep %s blocked" name))
              (while true
                (define [[e (go (.get queue))]]
                  (if (= (.get e "status") "start")
                    (define [[container (go (.show (get e "container")))]
                             [cname (.lstrip (get container "Name") "/")]]
                      (if (= cname name)
                        (do
                          (go (.sleep asyncio 1))
                          ; XXX: Run check after this to ensure it's up
                          (print (% " => dep %s unblocked" name))
                          (break))))))))
              (do
                (go (.sleep asyncio 1))
                (print (% " => dep %s is already up" name))))) x)
        [x [~@deps]])))))


(defn wheatley-create [data]
  "Central creation code"
  (defn write-binds [binds]
    (let [[ret `{}]]
      (for [(, k v) binds]
        (setv ret (+ ret `[~v `{}])))
      ret))

  (defn write-ports [ports]
    (let [[ret `{}]]
      (for [port ports]
        (setv (, ip, _, v) (.split port ":"))
        (setv ret (+ ret `[~(HyString v) `{}])))
      ret))

  (define [[name (one `nil (:name data))]
           [volumes (write-binds (:volumes data))]
           [env (HyList (list-comp (HyString (.join "=" x)) [x (:env data)]))]
           [ports (write-ports (:port-mapping data))]
           [image (one `"debian:stable" (:image data))]]
    `(do
      (go-setv container (.create-or-replace docker.containers
                            ~name {"Cmd" [~@(:run data)]
                                   "Image" ~image
                                   "Env" ~env
                                   "AttachStdin" false
                                   "AttachStdout" true
                                   "AttachStderr" true
                                   "ExposedPorts" ~ports
                                   "Tty" false
                                   "Volumes" ~volumes
                                   "OpenStdin" false
                                   "StdinOnce" false})))))


(defmacro job [&rest forms]
  (define [[data (group-map keyword? forms)]
           [creation-code (wheatley-create data)]
           [run-code (wheatley-run data)]]
    ; XXX: Remove `name' if it exists.

    `(run-every ~@(:every data)
      (disown
        ~creation-code
        (broadcast "job" nil "setup" container)
        ~run-code
        (broadcast "job" nil "start" container)
        (go (.wait container))
        (broadcast "job" nil "finished" container)
        (go-setv info (.show container))
        (if (= (int (-> info (get "State") (get "ExitCode"))) 0)
          (broadcast "job" nil "succeeded" container)
          (broadcast "job" nil "failed" container))
        (go (.delete container))
        (broadcast "job" nil "deleted" container)))))


(defmacro daemon [&rest forms]
  (define [[data (group-map keyword? forms)]
           [name (one `nil (:name data))]
           [depwait-code (wheatley-depwait data)]
           [creation-code (wheatley-create data)]
           [run-code (wheatley-run data)]]
    `(disown
      (while true
        ~creation-code
        (broadcast "daemon" ~name "setup" container)

        ;;; ok, we need something. let's block.
        (broadcast "daemon" ~name "pending" container)
        ~depwait-code
        (broadcast "daemon" ~name "released" container)

        ~run-code
        (broadcast "daemon" ~name "start" container)
        (go (.wait container))
        (broadcast "daemon" ~name "died" container)))))


(defmacro wheatley [set-name &rest body]
  `(marx

    (print "                .,-:;//;:=,
            . :H@@@MM@M#H/.,+%;,
         ,/X+ +M@@M@MM%=,-%HMMM@X/,
       -+@MM; $M@@MH+-,;XMMMM@MMMM@+-
      ;@M@@M- XM@X;. -+XXXXXHHH@M@M#@/.
    ,%MM@@MH ,@%=            .---=-=:=,.           [ WHEATLEY ]
    =@#@@@MX .,              -%HX$$%%%+;
   =-./@M@M$                  .;@MMMM@MM:
   X@/ -$MM/                    .+MM@@@M$
  ,@M@H: :@:                    . =X#@@@@-  Good news: that is NOT a docking
  ,@@@MMX, .                    /H- ;@M@M=  station. So there's one mystery
  .H@@@@M@+,                    %MM+..%#$.  solved. I'm going to attempt a
   /MMMM@MMH/.                  XM@MH; =;   manual override on this wall.
    /%+%$XHH@$=              , .H@@@@MX,    Could get a bit technical!
     .=--------.           -%H.,@@@@@MX,    Hold on!
     .%MM@@@HHHXX$$$%+- .:$MMX =M@@MM%.
       =XMMM@MM@MM#H;,-+HMM@M+ /MMMX=
         =%@M@M#@$-.=$@MM@@@M; %M%=
           ,:+$+-,/H#MMMMMMM@= =,
                 =++%%%%+/:-.
")

    (on :wheatley (wheatley-debug (slice (get event "id") 0 8) ":"
                      (get event "class")
                      (get event "name") (get event "event")))
    ~@body))
