(require acid.language)
(import [collections [defaultdict]]
        [functools [reduce]]
        asyncio)


(defn one [default args]
  "Get a single element back from the keyvector"
  (cond
    [(= (len args) 0) default]
    [(= (len args) 1) (get args 0)]
    [true (raise (TypeError "Too many args passed in."))]))


(defn key-value-stream [key? stream]
  "Stream the key-value pairs back"
  (let [[key nil]]
    (for [x stream]
      (if (key? x)
        (setv key x)
        (yield [key x])))))


(defn group-map [key? stream]
  "Create a defaultdict from a keyvector"
  (reduce
    (fn [accum v]
      (let [[(, key value) v]]
        (.append (get accum key) value))
      accum)
    (key-value-stream key? stream)
    (defaultdict list)))


(defn wheatley-create-container-config [mapping]
  "Create a Docker config from a keyvector defaultdict"
  (let [[dmap (group-map keyword? mapping)]
        [name (one nil (:name dmap))]
        [env (list-comp (.join "=" x) [x (:env dmap)])]
        [image (one "debian:stable" (:image dmap))]
        [volumes (dict-comp v {} [(, k v) (:volumes dmap)])]

        [ports ((fn [mappings]
                  (setv ret {})
                  (for [mapping mappings]
                    (setv (, ip, _, v) (.split mapping ":"))
                    (assoc ret v {}))
                  ret) (:port-mapping dmap))]

        [config {"Cmd" (:run dmap)
                 "Image" image
                 "Env" env
                 "AttachStdin" false
                 "AttachStdout" true
                 "AttachStderr" true
                 "ExposedPorts" ports
                 "Volumes" volumes
                 "Tty" false
                 "OpenStdin" false
                 "StdinOnce" false}]]
      config))

(defn wheatley-create-run-config [mapping]
  "Create a Docker run config from a keyvector defaultdict"
  (let [[dmap (group-map keyword? mapping)]
        [name (one nil (:name dmap))]
        [privileged (one false (:privileged dmap))]
        [binds (list-comp (.join ":" x) [x (:volumes dmap)])]
        [links (list-comp (.join ":" x) [x (:links dmap)])]
        [ports ((fn [mappings]
                 (setv ret {})
                 (for [mapping mappings]
                   (setv (, ip cport hport)
                         (.split mapping ":" 2))
                   (assoc ret hport [{"HostIp" ip
                                      "HostPort" cport}]))
                 (if (= ret {}) nil ret)) (:port-mapping dmap))]
        [config {"Binds" binds
                 "Privileged" privileged
                 "PortBindings" ports
                 "Links" links}]]
    config))


(eval-when-compile
  ;;; helper for wheatley-depwait
  (defmacro/g! ap-events [&rest body]
    `(do (setv ~g!queue (.listen docker.events))
         (while true
           (setv it (go (.get ~g!queue)))
           ~@body))))


(defn/coroutine wheatley-depwait [docker dependencies]
  "Depedency-wait code"
  (go (apply asyncio.gather
    (list-comp
      ((fn/coroutine [name]
        (setv running false)
        (try (do (setv container (go (.get docker.containers name)))
                 (setv running (-> (. container _container)
                                   (get "State")
                                   (get "Running"))))
        (except [ValueError]))

        (if (not running)
          (do (print (% " => dep %s not running. waiting..." name))
              (ap-events
                (if (= (.get it "status") "start")
                  (do (setv container (go (.show (get it "container"))))
                      (if (= (.lstrip (get container "Name") "/") name)
                      (do (print (% " => dep %s debounce" name))
                          ;; XXX: Better checking here.
                          (go (.sleep asyncio 2))

                          (try
                            (setv container (go (.show (get it "container"))))
                          (except [ValueError]
                            (print (% " => dep %s went down" name))
                            (continue)))

                          (print (% " => dep %s unblocked" name))
                          (break))))))))) x) [x dependencies]))))


(defn/coroutine wheatley-launch [docker name dependencies create-config run-config]
  "Launch a container with raw options"
  (go (wheatley-depwait docker dependencies))
  (setv container (go (.create-or-replace docker.containers name create-config)))
  (go (.start container run-config))
  (raise (StopIteration container)))


(defn/coroutine wheatley-simple-launch [docker config]
  "Launch a container with keyvector options"
  (setv dmap (group-map keyword? config))
  (setv name (one nil (:name dmap)))
  (if (is name nil) (raise (TypeError "No name supplied.")))
  (setv instance
    (go (wheatley-launch
          docker
          name
          (:requires dmap)
          (wheatley-create-container-config config)
          (wheatley-create-run-config config))))
  (raise (StopIteration instance)))
