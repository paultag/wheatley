;;;;
;;;;
;;;;
;;;;

(require lenin.language)


(lenin "services"

  ;;
  ;; MongoDB
  ;;
  (daemon :name "mongodb"
          :image "paultag/mongodb"
          :volumes ["/srv/leliel.pault.ag/dev/mongodb" "/var/lib/mongodb"]
          :run "/usr/local/bin/paultag-mongodb")

  ;;
  ;; OpenVPN
  ;;
  (daemon :name "openvpn"
          :privileged true
          :port-mapping "0.0.0.0:1194:1194/udp"
                        "0.0.0.0:443:443/tcp"
          :image "openvpn"
          :run "/usr/bin/paultag-openvpnd")

  ;;
  ;; OpenVPN
  ;;
  (daemon :name "nginx"
          :port-mapping "0.0.0.0:80:80/tcp"
          :image "paultag/nginx"
          :volumes ["/srv/leliel.pault.ag/dev/nginx/sites-enabled/"
                    "/etc/nginx/sites-enabled/"]
          :run "/usr/sbin/nginx"
               "-c" "/etc/nginx/nginx.conf"
               "-g" "daemon off;")

  ;;
  ;;PostgreSQL
  ;;
  (daemon :name "postgres"
          :image "paultag/postgres"
          :volumes ["/srv/leliel.pault.ag/dev/postgres/9.3/main"
                    "/var/lib/postgresql/9.3/main"]
          :run "/usr/local/bin/paultag-psqld"))
