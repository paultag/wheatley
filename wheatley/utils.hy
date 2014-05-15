;;;;;
;;;;;
;;;;;

(require acid.language)
(import [collections [defaultdict]]
        [functools [reduce]]
        asyncio)


(defn one [default args]
  (cond
    [(= (len args) 0) default]
    [(= (len args) 1) (get args 0)]
    [true (raise (TypeError "Too many args passed in."))]))


(defn key-value-stream [key? stream]
  (let [[key nil]]
    (for [x stream]
      (if (key? x)
        (setv key x)
        (yield [key x])))))


(defn group-map [key? stream]
  (reduce
    (fn [accum v]
      (let [[(, key value) v]]
        (.append (get accum key) value))
      accum)
    (key-value-stream key? stream)
    (defaultdict list)))


(eval-when-compile
  ;;; helper for wheatley-depwait
  (defmacro/g! ap-events [&rest body]
    `(do (setv ~g!queue (.listen docker.events))
         (while true
           (setv it (go (.get ~g!queue)))
           ~@body))))


(defn/coroutine wheatley-depwait [docker dependencies]
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
  (go (wheatley-depwait docker dependencies))
  (setv container (go (.create-or-replace docker.containers name create-config)))
  (go (.start container run-config))
  (raise (StopIteration container)))
