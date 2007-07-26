(in-package :parenscript)

(defun warn-deprecated (old-name new-name)
  (warn (format nil "~:@(~a~) is deprecated. Use ~:@(~a~) instead." old-name new-name)))

;;; DEPRECATED INTERFACE ;;;

(defun js-equal (a b)
  (warn-deprecated 'js-equal 'script-equal)
  (script-equal a b))

(defun js-compile (form)
  (warn-deprecated 'js-compile 'compile-script)
  (compile-script form :output-spec :javascript))

(defun js-compile-list (form)
  (warn-deprecated 'js-compile-list 'compile-script)
  (compile-script form :output-spec :javascript))

(defun js-gensym (&rest args)
  (warn-deprecated 'js-gensym 'script-gensym)
  (apply #'script-gensym args))

(defmacro defjsmacro (&rest args)
  (warn-deprecated 'defjsmacro 'defscriptmacro)
  `(defscriptmacro ,@args))

(defmacro js (&body body)
  (warn-deprecated 'js 'ps)
  `(script ,@body))

(defmacro js* (&body body)
  (warn-deprecated 'js* 'ps*)
  `(script* ,@body))

(defun js-to-string (expr)
  "Given an AST node, compiles it to a Javascript string."
  (warn "JS-TO-STRING is deprecated.")
  (string-join
   (ps-js::js-to-statement-strings (compile-script-form expr) 0)
   (string #\Newline)))

(defun js-to-line (expr)
  "Given an AST node, compiles it to a Javascript string."
  (warn "JS-TO-LINE is deprecated.")
  (string-join
   (ps-js::js-to-statement-strings (compile-script-form expr) 0) " "))

(defmacro js-file (&rest body)
  (warn "JS-FILE is deprecated.")
  `(html
    (:princ
     (js ,@body))))

(defmacro js-script (&rest body)
  (warn "JS-SCRIPT is deprecated.")
  `((:script :type "text/javascript")
    (:princ (format nil "~%// <![CDATA[~%"))
    (:princ (js ,@body))
    (:princ (format nil "~%// ]]>~%"))))

(defmacro js-inline (&rest body)
  (warn "JS-INLINE is deprecated.")
  `(js-inline* '(progn ,@body)))

(defmacro js-inline* (&rest body)
  (warn "JS-INLINE* is deprecated.")
  `(concatenate 'string "javascript:"
    (string-join (js-to-statement-strings (compile-script-form (list 'progn ,@body)) 0) " ")))

(defmacro with-unique-js-names (&rest args)
  (warn-deprecated 'with-unique-js-names 'with-unique-ps-names)
  `(with-unique-ps-names ,@args))

(defmacro gen-js-name (&rest args)
  (warn-deprecated 'gen-js-name 'gen-ps-name)
  `(gen-ps-name ,@args))

(defmacro gen-js-name-string (&rest args)
  (warn-deprecated 'gen-js-name-string 'gen-script-name-string)
  `(gen-script-name-string ,@args))