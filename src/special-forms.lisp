(in-package "PARENSCRIPT")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; literals
(defmacro defpsliteral (name string)
  `(progn
     (add-ps-literal ',name)
     (define-ps-special-form ,name ()
       (list 'js:literal ,string))))

(defpsliteral this      "this")
(defpsliteral t         "true")
(defpsliteral true      "true")
(defpsliteral false     "false")
(defpsliteral f         "false")
(defpsliteral nil       "null")
(defpsliteral undefined "undefined")

(macrolet ((def-for-literal (name printer)
             `(progn
                (add-ps-literal ',name)
                (define-ps-special-form ,name (&optional label)
                  (list ',printer label)))))
  (def-for-literal break js:break)
  (def-for-literal continue js:continue))

(defpsmacro quote (x)
  (typecase x
    (cons (cons 'array (mapcar (lambda (x) (when x `',x)) x)))
    (null '(array))
    (keyword x)
    (symbol (symbol-to-js-string x))
    (number x)
    (string x)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; unary operators
(macrolet ((def-unary-ops (&rest ops)
             `(progn ,@(mapcar (lambda (op)
                                 (let ((op (if (listp op) (car op) op))
                                       (spacep (if (listp op) (second op) nil)))
                                   `(define-ps-special-form ,op (x)
                                      (list 'js:unary-operator ',op
                                            (compile-parenscript-form x :expecting :expression)
                                            :prefix t :space ,spacep))))
                               ops))))
  (def-unary-ops ~ ! (new t) (delete t) (void t) (typeof t)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; statements
(define-ps-special-form return (&optional value)
  `(js:return ,(compile-parenscript-form value :expecting :expression)))

(define-ps-special-form throw (value)
  `(js:throw ,(compile-parenscript-form value :expecting :expression)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; arrays
(define-ps-special-form array (&rest values)
  `(js:array ,@(mapcar (lambda (form) (compile-parenscript-form form :expecting :expression))
                               values)))

(define-ps-special-form aref (array &rest coords)
  `(js:aref ,(compile-parenscript-form array :expecting :expression)
            ,(mapcar (lambda (form)
                       (compile-parenscript-form form :expecting :expression))
                     coords)))

(defpsmacro list (&rest values)
  `(array ,@values))

(defpsmacro make-array (&rest initial-values)
  `(new (*array ,@initial-values)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; operators
(define-ps-special-form incf (x &optional (delta 1))
  (if (eql delta 1)
      `(js:unary-operator js:++ ,(compile-parenscript-form x :expecting :expression) :prefix t)
      `(js:operator js:+= ,(compile-parenscript-form x :expecting :expression)
                    ,(compile-parenscript-form delta :expecting :expression))))

(define-ps-special-form decf (x &optional (delta 1))
  (if (eql delta 1)
      `(js:unary-operator js:-- ,(compile-parenscript-form x :expecting :expression) :prefix t)
      `(js:operator js:-= ,(compile-parenscript-form x :expecting :expression)
                    ,(compile-parenscript-form delta :expecting :expression))))

(define-ps-special-form - (first &rest rest)
  (if rest
      `(js:operator js:- ,@(mapcar (lambda (val) (compile-parenscript-form val :expecting :expression))
                                   (cons first rest)))
      `(js:unary-operator js:- ,(compile-parenscript-form first :expecting :expression) :prefix t)))

(define-ps-special-form not (x)
  (let ((form (compile-parenscript-form x :expecting :expression))
        inverse-op)
    (if (and (eq (car form) 'js:operator)
             (= (length (cddr form)) 2)
             (setf inverse-op (case (cadr form)
                                (== '!=)
                                (< '>=)
                                (> '<=)
                                (<= '>)
                                (>= '<)
                                (!= '==)
                                (=== '!==)
                                (!== '===))))
        `(js:operator ,inverse-op ,@(cddr form))
        `(js:unary-operator js:! ,form :prefix t))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; control structures
(defun flatten-blocks (body)
  (when body
    (if (and (listp (car body))
             (eq 'js:block (caar body)))
        (append (cdr (car body)) (flatten-blocks (cdr body)))
        (cons (car body) (flatten-blocks (cdr body))))))

(defun constant-literal-form-p (form)
  (or (numberp form)
      (stringp form)
      (and (listp form)
           (eq 'js:literal (car form)))))

(define-ps-special-form progn (&rest body)
  (if (and (eq expecting :expression) (= 1 (length body)))
      (compile-parenscript-form (car body) :expecting :expression)
      `(,(if (eq expecting :expression) 'js:|,| 'js:block)
         ,@(let* ((block (flatten-blocks (remove nil (mapcar (lambda (form)
                                                               (compile-parenscript-form form :expecting expecting))
                                                             body)))))
                 (append (remove-if #'constant-literal-form-p (butlast block)) (last block))))))

(define-ps-special-form cond (&rest clauses)
  (ecase expecting
    (:statement `(js:if ,(compile-parenscript-form (caar clauses) :expecting :expression)
                        ,(compile-parenscript-form `(progn ,@(cdar clauses)))
                        ,@(loop for (test . body) in (cdr clauses) appending
                               (if (eq t test)
                                   `(:else ,(compile-parenscript-form `(progn ,@body) :expecting :statement))
                                   `(:else-if ,(compile-parenscript-form test :expecting :expression)
                                              ,(compile-parenscript-form `(progn ,@body) :expecting :statement))))))
    (:expression (make-cond-clauses-into-nested-ifs clauses))))

(defun make-cond-clauses-into-nested-ifs (clauses)
  (if clauses
      (destructuring-bind (test &rest body)
          (car clauses)
        (if (eq t test)
            (compile-parenscript-form `(progn ,@body) :expecting :expression)
            `(js:? ,(compile-parenscript-form test :expecting :expression)
                   ,(compile-parenscript-form `(progn ,@body) :expecting :expression)
                   ,(make-cond-clauses-into-nested-ifs (cdr clauses)))))
      (compile-parenscript-form nil :expecting :expression))) ;; js:null

(define-ps-special-form if (test then &optional else)
  (ecase expecting
    (:statement `(js:if ,(compile-parenscript-form test :expecting :expression)
                        ,(compile-parenscript-form `(progn ,then))
                        ,@(when else `(:else ,(compile-parenscript-form `(progn ,else))))))
    (:expression `(js:? ,(compile-parenscript-form test :expecting :expression)
                        ,(compile-parenscript-form then :expecting :expression)
                        ,(compile-parenscript-form else :expecting :expression)))))

(define-ps-special-form switch (test-expr &rest clauses)
  `(js:switch ,(compile-parenscript-form test-expr :expecting :expression)
     ,(loop for (val . body) in clauses collect
           (cons (if (eq val 'default)
                     'default
                     (compile-parenscript-form val :expecting :expression))
                 (mapcar (lambda (x) (compile-parenscript-form x :expecting :statement))
                         body)))))

(defpsmacro case (value &rest clauses)
  (labels ((make-clause (val body more)
             (cond ((and (listp val) (not (eq (car val) 'quote)))
                    (append (mapcar #'list (butlast val))
                            (make-clause (first (last val)) body more)))
                   ((member val '(t otherwise))
                    (make-clause 'default body more))
                   (more `((,val ,@body break)))
                   (t `((,val ,@body))))))
    `(switch ,value ,@(mapcon (lambda (clause)
                                (make-clause (car (first clause))
                                             (cdr (first clause))
                                             (rest clause)))
                              clauses))))

(defpsmacro when (test &rest body)
  `(if ,test (progn ,@body)))

(defpsmacro unless (test &rest body)
  `(if (not ,test) (progn ,@body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; function definition
(defun compile-function-definition (args body)
  (list (mapcar (lambda (arg) (compile-parenscript-form arg :expecting :symbol)) args)
        (let* ((*enclosing-lexical-block-declarations* ())
               (body (compile-parenscript-form `(progn ,@body)))
               (var-decls (compile-parenscript-form
                           `(progn ,@(mapcar (lambda (var) `(var ,var)) *enclosing-lexical-block-declarations*)))))
          `(js:block ,@(cdr var-decls) ,@(cdr body)))))

(define-ps-special-form %js-lambda (args &rest body)
  `(js:lambda ,@(compile-function-definition args body)))

(define-ps-special-form %js-defun (name args &rest body)
  `(js:defun ,name ,@(compile-function-definition args body)))

(defun parse-function-body (body)
  (let* ((docstring
          (when (stringp (first body))
            (first body)))
         (body-forms (if docstring (rest body) body)))
    (values body-forms docstring)))

(defun parse-key-spec (key-spec)
  "parses an &key parameter.  Returns 5 values:
var, init-form,  keyword-name, supplied-p-var, init-form-supplied-p.

Syntax of key spec:
[&key {var | ({var | (keyword-name var)} [init-form [supplied-p-parameter]])}*
"
  (let* ((var (cond ((symbolp key-spec) key-spec)
                    ((and (listp key-spec) (symbolp (first key-spec))) (first key-spec))
                    ((and (listp key-spec) (listp (first key-spec)))   (second (first key-spec)))))
         (keyword-name (if (and (listp key-spec) (listp (first key-spec)))
                           (first (first key-spec))
                           (intern (string var) :keyword)))
         (init-form (if (listp key-spec) (second key-spec) nil))
         (init-form-supplied-p (if (listp key-spec) t nil))
         (supplied-p-var (if (listp key-spec) (third key-spec) nil)))
    (values var init-form keyword-name supplied-p-var init-form-supplied-p)))

(defun parse-optional-spec (spec)
  "Parses an &optional parameter.  Returns 3 values: var, init-form, supplied-p-var.
[&optional {var | (var [init-form [supplied-p-parameter]])}*] "
  (let* ((var (cond ((symbolp spec) spec)
                    ((and (listp spec) (first spec)))))
         (init-form (if (listp spec) (second spec)))
         (supplied-p-var (if (listp spec) (third spec))))
    (values var init-form supplied-p-var)))
  
(defun parse-aux-spec (spec)
  "Returns two values: variable and init-form"
  ;; [&aux {var | (var [init-form])}*])
  (values (if (symbolp spec) spec (first spec))
          (when (listp spec) (second spec))))

(defpsmacro defaultf (place value)
  `(when (=== ,place undefined)
     (setf ,place ,value)))

(defun parse-extended-function (lambda-list body &optional name)
  "Returns two values: the effective arguments and body for a function with
the given lambda-list and body."

  ;; The lambda list is transformed as follows, since a javascript lambda list is just a 
  ;; list of variable names, and you have access to the arguments variable inside the function:
  ;; * standard variables are the mapped directly into the js-lambda list
  ;; * optional variables' variable names are mapped directly into the lambda list,
  ;;   and for each optional variable with name v and default value d, a form is produced
  ;;   (defaultf v d)
  ;; * keyword variables are not included in the js-lambda list, but instead are
  ;;   obtained from the magic js ARGUMENTS pseudo-array. Code assigning values to
  ;;   keyword vars is prepended to the body of the function.
  (declare (ignore name))
  (multiple-value-bind (requireds optionals rest? rest keys? keys allow? aux? aux
                                  more? more-context more-count key-object)
      (parse-lambda-list lambda-list)
    (declare (ignore allow? aux? aux more? more-context more-count key-object))
    (let* (;; optionals are of form (var default-value)
           (effective-args
            (remove-if
             #'null
             (append requireds
                     (mapcar #'parse-optional-spec optionals))))
           (opt-forms
            (mapcar #'(lambda (opt-spec)
                        (multiple-value-bind (var val) (parse-optional-spec opt-spec)
                          `(defaultf ,var ,val)))
                    optionals))
           (key-forms
            (when keys?
              (if (< *js-target-version* 1.6)
                  (with-ps-gensyms (n)
                    (let ((decls nil) (assigns nil) (defaults nil))
                      (mapc (lambda (k)
                              (multiple-value-bind (var init-form keyword-str)
                                  (parse-key-spec k)
                                (push `(var ,var) decls)
                                (push `(,keyword-str (setf ,var (aref arguments (1+ ,n)))) assigns)
                                (push (list 'defaultf var init-form) defaults)))
                            (reverse keys))
                      `(,@decls
                        (loop :for ,n :from ,(length requireds)
                           :below (length arguments) :by 2 :do
                           (case (aref arguments ,n) ,@assigns))
                        ,@defaults)))
                  (mapcar (lambda (k)
                            (multiple-value-bind (var init-form keyword-str)
                                (parse-key-spec k)
                              (with-ps-gensyms (x)
                                `(let ((,x ((@ *Array prototype index-of call) arguments ,keyword-str ,(length requireds))))
                                   (var ,var (if (= -1 ,x) ,init-form (aref arguments (1+ ,x))))))))
                          keys))))
           (rest-form
            (if rest?
                (with-ps-gensyms (i)
                  `(progn (var ,rest (array))
                    (dotimes (,i (- (slot-value arguments 'length) ,(length effective-args)))
                      (setf (aref ,rest ,i) (aref arguments (+ ,i ,(length effective-args)))))))
                `(progn)))
           (body-paren-forms (parse-function-body body)) ; remove documentation
           (effective-body (append opt-forms key-forms (list rest-form) body-paren-forms)))
      (values effective-args effective-body))))

(defpsmacro defun (name lambda-list &body body)
  "An extended defun macro that allows cool things like keyword arguments.
lambda-list::=
 (var* 
  [&optional {var | (var [init-form [supplied-p-parameter]])}*] 
  [&rest var] 
  [&key {var | ({var | (keyword-name var)} [init-form [supplied-p-parameter]])}* [&allow-other-keys]] 
  [&aux {var | (var [init-form])}*])"
  (if (symbolp name)
      `(defun-function ,name ,lambda-list ,@body)
      (progn (assert (and (listp name) (= (length name) 2) (eq 'setf (car name))) ()
                     "(defun ~s ~s ...) needs to have a symbol or (setf symbol) for a name." name lambda-list)
             `(defun-setf ,name ,lambda-list ,@body))))

(defpsmacro defun-function (name lambda-list &body body)
  (multiple-value-bind (effective-args effective-body)
      (parse-extended-function lambda-list body name)
    `(%js-defun ,name ,effective-args
      ,@effective-body)))

(defvar *defun-setf-name-prefix* "__setf_")

(defpsmacro defun-setf (setf-name lambda-list &body body)
  (let ((mangled-function-name (intern (concatenate 'string *defun-setf-name-prefix* (symbol-name (second setf-name)))
                                       (symbol-package (second setf-name))))
        (function-args (cdr (ordered-set-difference lambda-list lambda-list-keywords))))
    `(progn (defsetf ,(second setf-name) ,(cdr lambda-list) (store-var)
              `(,',mangled-function-name ,store-var ,@(list ,@function-args)))
            (defun ,mangled-function-name ,lambda-list ,@body))))

(defpsmacro lambda (lambda-list &body body)
  "An extended defun macro that allows cool things like keyword arguments.
lambda-list::=
 (var* 
  [&optional {var | (var [init-form [supplied-p-parameter]])}*] 
  [&rest var] 
  [&key {var | ({var | (keyword-name var)} [init-form [supplied-p-parameter]])}* [&allow-other-keys]] 
  [&aux {var | (var [init-form])}*])"
  (multiple-value-bind (effective-args effective-body)
      (parse-extended-function lambda-list body)
    `(%js-lambda ,effective-args
      ,@effective-body)))

(defpsmacro flet (fn-defs &rest body)
  (flet ((process-fn-def (def)
           `(var ,(car def) (lambda ,@(cdr def)))))
    `(progn ,@(mapcar #'process-fn-def fn-defs) ,@body)))

(defpsmacro labels (fn-defs &rest body)
  (flet ((process-fn-def (def)
           `(var ,(car def) (defun ,(car def) ,@(cdr def)))))
    `(progn ,@(mapcar #'process-fn-def fn-defs) ,@body)))

(defpsmacro defsetf-long (access-fn lambda-list (store-var) form)
  (setf (get-macro-spec access-fn *ps-setf-expanders*)
        (compile nil
                 (let ((var-bindings (ordered-set-difference lambda-list lambda-list-keywords)))
                   `(lambda (access-fn-args store-form)
                     (destructuring-bind ,lambda-list
                               access-fn-args
                       (let* ((,store-var (ps-gensym))
                              (gensymed-names (loop repeat ,(length var-bindings) collecting (ps-gensym)))
                              (gensymed-arg-bindings (mapcar #'list gensymed-names (list ,@var-bindings))))
                         (destructuring-bind ,var-bindings
                             gensymed-names
                           `(let* (,@gensymed-arg-bindings
                                   (,,store-var ,store-form))
                             ,,form))))))))
  nil)

(defpsmacro defsetf-short (access-fn update-fn &optional docstring)
  (declare (ignore docstring))
  (setf (get-macro-spec access-fn *ps-setf-expanders*)
        (lambda (access-fn-args store-form)
          `(,update-fn ,@access-fn-args ,store-form)))
  nil)

(defpsmacro defsetf (access-fn &rest args)
  `(,(if (= (length args) 3) 'defsetf-long 'defsetf-short) ,access-fn ,@args))

(defpsmacro funcall (&rest arg-form)
  arg-form)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; macros
(defmacro with-temp-macro-environment ((var) &body body)
  `(let* ((,var (make-macro-env-dictionary))
          (*ps-macro-env* (cons ,var *ps-macro-env*)))
    ,@body))

(define-ps-special-form macrolet (macros &body body)
  (with-temp-macro-environment (macro-env-dict)
    (dolist (macro macros)
      (destructuring-bind (name arglist &body body)
          macro
        (setf (get-macro-spec name macro-env-dict)
              (cons nil (eval (make-ps-macro-function arglist body))))))
    (compile-parenscript-form `(progn ,@body))))

(define-ps-special-form symbol-macrolet (symbol-macros &body body)
  (with-temp-macro-environment (macro-env-dict)
    (dolist (macro symbol-macros)
      (destructuring-bind (name expansion)
          macro
        (setf (get-macro-spec name macro-env-dict)
              (cons t (lambda (x) (declare (ignore x)) expansion)))))
    (compile-parenscript-form `(progn ,@body))))

(define-ps-special-form defmacro (name args &body body) ;; should this be a macro?
  (eval `(defpsmacro ,name ,args ,@body))
  nil)

(define-ps-special-form define-symbol-macro (name expansion) ;; should this be a macro?
  (eval `(define-ps-symbol-macro ,name ,expansion))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; objects
(add-ps-literal '{})
(define-ps-symbol-macro {} (create))

(define-ps-special-form create (&rest arrows)
  `(js:object ,@(loop for (key-expr val-expr) on arrows by #'cddr collecting
                     (let ((key (compile-parenscript-form key-expr :expecting :expression)))
                       (when (keywordp key)
                         (setf key `(js:variable ,key)))
                       (assert (or (stringp key)
                                   (numberp key)
                                   (and (listp key)
                                        (or (eq 'js:variable (car key))
                                            (eq 'quote (car key)))))
                               ()
                               "Slot key ~s is not one of js-variable, keyword, string or number." key)
                       (cons key (compile-parenscript-form val-expr :expecting :expression))))))

(define-ps-special-form %js-slot-value (obj slot)
  `(js:slot-value ,(compile-parenscript-form obj :expecting :expression)
                  ,(if (and (listp slot) (eq 'quote (car slot)))
                       (second slot) ;; assume we're quoting a symbol
                       (compile-parenscript-form slot))))

(define-ps-special-form instanceof (value type)
  `(js:instanceof ,(compile-parenscript-form value :expecting :expression)
                  ,(compile-parenscript-form type :expecting :expression)))

(defpsmacro slot-value (obj &rest slots)
  (if (null (rest slots))
      `(%js-slot-value ,obj ,(first slots))
      `(slot-value (slot-value ,obj ,(first slots)) ,@(rest slots))))

(defpsmacro with-slots (slots object &rest body)
  (flet ((slot-var (slot) (if (listp slot) (first slot) slot))
         (slot-symbol (slot) (if (listp slot) (second slot) slot)))
    `(symbol-macrolet ,(mapcar #'(lambda (slot)
                                   `(,(slot-var slot) (slot-value ,object ',(slot-symbol slot))))
                               slots)
      ,@body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; assignment and binding
(defun assignment-op (op)
  (case op
    (+ '+=)
    (~ '~=)
    (\& '\&=)
    (\| '\|=)
    (- '-=)
    (* '*=)
    (% '%=)
    (>> '>>=)
    (^  '^=)
    (<< '<<=)
    (>>> '>>>=)
    (/   '/=)
    (t   nil)))

(define-ps-special-form setf1% (lhs rhs)
  (let ((lhs (compile-parenscript-form lhs :expecting :expression))
        (rhs (compile-parenscript-form rhs :expecting :expression)))
    (if (and (listp rhs)
             (eq 'js:operator (car rhs))
             (member (cadr rhs) '(+ *))
             (equalp lhs (caddr rhs)))
        `(js:operator ,(assignment-op (cadr rhs)) ,lhs (js:operator ,(cadr rhs) ,@(cdddr rhs)))
        `(js:= ,lhs ,rhs))))

(defpsmacro setf (&rest args)
  (flet ((process-setf-clause (place value-form)
           (if (and (listp place) (get-macro-spec (car place) *ps-setf-expanders*))
               (funcall (get-macro-spec (car place) *ps-setf-expanders*) (cdr place) value-form)
               (let ((exp-place (ps-macroexpand place)))
                 (if (and (listp exp-place) (get-macro-spec (car exp-place) *ps-setf-expanders*))
                     (funcall (get-macro-spec (car exp-place) *ps-setf-expanders*) (cdr exp-place) value-form)
                     `(setf1% ,exp-place ,value-form))))))
    (assert (evenp (length args)) ()
            "~s does not have an even number of arguments." (cons 'setf args))
    `(progn ,@(loop for (place value) on args by #'cddr collect (process-setf-clause place value)))))

(defpsmacro psetf (&rest args)
  (let ((places (loop for x in args by #'cddr collect x))
        (vals (loop for x in (cdr args) by #'cddr collect x)))
    (let ((gensyms (mapcar (lambda (x) (declare (ignore x)) (ps-gensym)) places)))
      `(let ,(mapcar #'list gensyms vals)
         (setf ,@(mapcan #'list places gensyms))))))

(defun check-setq-args (args)
  (let ((vars (loop for x in args by #'cddr collect x)))
    (let ((non-var (find-if (complement #'symbolp) vars)))
      (when non-var
        (error 'type-error :datum non-var :expected-type 'symbol)))))

(defpsmacro setq (&rest args)
  (check-setq-args args)
  `(setf ,@args))

(defpsmacro psetq (&rest args)
  (check-setq-args args)
  `(psetf ,@args))

(define-ps-special-form var (name &optional (value (values) value-provided?) documentation)
  (declare (ignore documentation))
  (ecase expecting
    (:statement
     `(js:var ,name ,@(when value-provided?
                            (list (compile-parenscript-form value :expecting :expression)))))
    (:expression
     (push name *enclosing-lexical-block-declarations*)
     (when value-provided?
       (compile-parenscript-form `(setf ,name ,value) :expecting :expression)))))

(defpsmacro defvar (name &optional (value (values) value-provided?) documentation)
  ;; this must be used as a top-level form, otherwise the resulting behavior will be undefined.
  (declare (ignore documentation))
  (pushnew name *ps-special-variables*)
  `(var ,name ,@(when value-provided? (list value))))

(defpsmacro let (bindings &body body)
  (flet ((add-renamed-vars (bindings predicate)
           (mapcar (lambda (x) (append x (list (ps-gensym (car x)))))
                   (remove-if predicate bindings :key #'car)))
         (var (x) (first x))
         (val (x) (second x))
         (renamed (x) (third x)))
    (let* ((normalized-bindings (mapcar (lambda (x) (if (symbolp x) `(,x nil) x)) bindings))
           (lexical-bindings (add-renamed-vars normalized-bindings #'ps-special-variable-p))
           (dynamic-bindings (add-renamed-vars normalized-bindings (complement #'ps-special-variable-p)))
           (renamed-body `(symbol-macrolet ,(mapcar (lambda (x) (list (var x) (renamed x)))
                                                    lexical-bindings)
                            ,@body)))
    `(progn
       ,@(mapcar (lambda (x) `(var ,(renamed x) ,(val x))) lexical-bindings)
       ,(if dynamic-bindings
            `(progn ,@(mapcar (lambda (x) `(var ,(renamed x))) dynamic-bindings)
                    (try (progn (setf ,@(loop for x in dynamic-bindings append
                                             `(,(renamed x) ,(var x)
                                               ,(var x) ,(val x))))
                                ,renamed-body)
                         (:finally
                          (setf ,@(mapcan (lambda (x) `(,(var x) ,(renamed x))) dynamic-bindings)))))
            renamed-body)))))

(defpsmacro let* (bindings &body body)
  (if bindings
      `(let (,(car bindings))
         (let* ,(cdr bindings)
           ,@body))
      `(progn ,@body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; iteration
(defun make-for-vars/inits (init-forms)
  (mapcar (lambda (x)
            (cons (compile-parenscript-form (if (atom x) x (first x)) :expecting :symbol)
                  (compile-parenscript-form (if (atom x) nil (second x)) :expecting :expression)))
          init-forms))

(define-ps-special-form labeled-for (label init-forms cond-forms step-forms &rest body)
  `(js:for ,label
           ,(make-for-vars/inits init-forms)
           ,(mapcar (lambda (x) (compile-parenscript-form x :expecting :expression)) cond-forms)
           ,(mapcar (lambda (x) (compile-parenscript-form x :expecting :expression)) step-forms)
           ,(compile-parenscript-form `(progn ,@body))))

(defpsmacro for (init-forms cond-forms step-forms &body body)
  `(labeled-for nil ,init-forms ,cond-forms ,step-forms ,@body))

(defun do-make-let-bindings (decls)
  (mapcar (lambda (x)
            (if (atom x) x
                (if (endp (cdr x)) (list (car x))
                    (subseq x 0 2))))
          decls))

(defun do-make-init-vars (decls)
  (mapcar (lambda (x) (if (atom x) x (first x))) decls))

(defun do-make-init-vals (decls)
  (mapcar (lambda (x) (if (or (atom x) (endp (cdr x))) nil (second x))) decls))

(defun do-make-for-vars/init (decls)
  (mapcar (lambda (x)
            (if (atom x) x
                (if (endp (cdr x)) x
                    (subseq x 0 2))))
          decls))

(defun do-make-for-steps (decls)
  (mapcar (lambda (x)
            `(setf ,(first x) ,(third x)))
          (remove-if (lambda (x) (or (atom x) (< (length x) 3))) decls)))

(defun do-make-iter-psteps (decls)
  `(psetq
    ,@(mapcan (lambda (x) (list (first x) (third x)))
              (remove-if (lambda (x) (or (atom x) (< (length x) 3))) decls))))

(defpsmacro do* (decls (termination &optional (result nil result?)) &body body)
  (if result?
      `((lambda ()
          (for ,(do-make-for-vars/init decls) ((not ,termination)) ,(do-make-for-steps decls)
               ,@body)
          (return ,result)))
      `(progn
         (for ,(do-make-for-vars/init decls) ((not ,termination)) ,(do-make-for-steps decls)
              ,@body))))

(defpsmacro do (decls (termination &optional (result nil result?)) &body body)
  (if result?
      `((lambda ,(do-make-init-vars decls)
          (for () ((not ,termination)) ()
               ,@body
               ,(do-make-iter-psteps decls))
          (return ,result))
        ,@(do-make-init-vals decls))
      `(let ,(do-make-let-bindings decls)
         (for () ((not ,termination)) ()
              ,@body
              ,(do-make-iter-psteps decls)))))

(define-ps-special-form for-in ((var object) &rest body)
  `(js:for-in ,(compile-parenscript-form var :expecting :expression)
              ,(compile-parenscript-form object :expecting :expression)
              ,(compile-parenscript-form `(progn ,@body))))

(define-ps-special-form while (test &rest body)
  `(js:while ,(compile-parenscript-form test :expecting :expression)
     ,(compile-parenscript-form `(progn ,@body))))

(defpsmacro dotimes ((var count &optional (result nil result?)) &rest body)
  `(do* ((,var 0 (1+ ,var)))
        ((>= ,var ,count) ,@(when result? (list result)))
     ,@body))

(defpsmacro dolist ((var array &optional (result nil result?)) &body body)
  (let ((idx (ps-gensym "_js_idx"))
        (arrvar (ps-gensym "_js_arrvar")))
    `(do* (,var
           (,arrvar ,array)
           (,idx 0 (1+ ,idx)))
          ((>= ,idx (slot-value ,arrvar 'length))
           ,@(when result? (list result)))
       (setq ,var (aref ,arrvar ,idx))
       ,@body)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; misc
(define-ps-special-form with (expression &rest body)
  `(js:with ,(compile-parenscript-form expression :expecting :expression)
     ,(compile-parenscript-form `(progn ,@body))))

(define-ps-special-form try (form &rest clauses)
  (let ((catch (cdr (assoc :catch clauses)))
        (finally (cdr (assoc :finally clauses))))
    (assert (not (cdar catch)) nil "Sorry, currently only simple catch forms are supported.")
    (assert (or catch finally) ()
            "Try form should have either a catch or a finally clause or both.")
    `(js:try ,(compile-parenscript-form `(progn ,form))
          :catch ,(when catch (list (compile-parenscript-form (caar catch) :expecting :symbol)
                                   (compile-parenscript-form `(progn ,@(cdr catch)))))
          :finally ,(when finally (compile-parenscript-form `(progn ,@finally))))))

(define-ps-special-form cc-if (test &rest body)
  `(js:cc-if ,test ,@(mapcar #'compile-parenscript-form body)))

(define-ps-special-form regex (regex)
  `(js:regex ,(string regex)))

(define-ps-special-form lisp (lisp-form)
  ;; (ps (foo (lisp bar))) is in effect equivalent to (ps* `(foo ,bar))
  ;; when called from inside of ps*, lisp-form has access only to the dynamic environment (like for eval)
  `(js:escape (ps1* ,lisp-form)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; eval-when
(define-ps-special-form eval-when (situation-list &body body)
  "(eval-when (situation*) body-form*)

The body forms are evaluated only during the given SITUATION. The accepted SITUATIONS are
:load-toplevel, :compile-toplevel, and :execute.  The code in BODY-FORM is assumed to be
COMMON-LISP code in :compile-toplevel and :load-toplevel sitations, and parenscript code in
:execute.  "
  (when (and (member :compile-toplevel situation-list)
	     (member *toplevel-compilation-level* '(:toplevel :inside-toplevel-form)))
    (eval `(progn ,@body)))
  (if (member :execute situation-list)
      (compile-parenscript-form `(progn ,@body) :expecting expecting)
      (compile-parenscript-form `(progn) :expecting expecting)))