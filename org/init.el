;; see https://emacs.stackexchange.com/a/7633
(setq org-html-htmlize-output-type 'css)
(setq org-html-htmlize-font-prefix "org-")

(require 'ox-publish)

(defvar-local content-dir (expand-file-name "content" default-directory))
(defvar-local static-dir (expand-file-name "static" default-directory))
(defvar-local output-dir (expand-file-name "public" default-directory))

(setq org-publish-project-alist
      `(("sisu-content"
         :base-directory ,content-dir
         :base-extension "org"
         :publishing-directory ,output-dir
         :recursive t
         :publishing-function org-html-publish-to-html
         :headline-levels 4
         :auto-preamble t
         :auto-sitemap t
         :html-doctype "html5"
         :html-html5-fancy t)
        ("sisu-static"
         :base-directory ,static-dir
         :base-extension "css\\|ico\\|js\\|png\\|jpg\\|gif\\|pdf\\|txt"
         :publishing-directory ,output-dir
         :recursive t
         :publishing-function org-publish-attachment)
        ("www.sisu.io"
         :components ("sisu-content" "sisu-static"))))

(use-package ox-hugo
  :ensure t
  :after ox)
