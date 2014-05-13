(require wheatley.language)


(wheatley "services"

  ;;
  ;; Sync VCSs
  ;;
  (job :every 30 minutes
       :image "paultag/vcs"
       :volumes ["/srv/leliel.pault.ag/dev/vcs" "/vcs"]
       :run "/opt/paultag/vcs/docron"))
