;;; casi.el --- C-like Automatic Style Input

;; Copyright (C) 2006 Guanpeng Xu.

;; Maintainer: Guanpeng Xu <herberteuler@hotmail.com>
;; Keywords: c style

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; "Casi" refers to "C-like Automatic Style Input", which is a minor
;; mode that allows you to write C like languages programs more
;; conveniently.  It must work with CC mode, and will do the below two
;; things:

;;     - Invoke a function after invoking `c-set-style'.

;;     - Set different commands for the same key sequence in different
;;       styles.

;; You can fine tune settings after `c-set-style' finishing its job,
;; e.g. modify `c-offsets-alist', with the first function, and do some
;; extra work more than just inserting a character, e.g. insert some
;; characters when you type a key sequence, with the second function.
;; This way, you can input programs in different styles while keeping
;; a same key-pressing style.

;; For example, people who like bsd style will input a C program like
;; this:

;;     int main(int argc, char *argv[])
;;     {
;;             printf("hello,world\n");
;;             return 0;
;;     }

;; If such people want Emacs to insert a space automatically when they
;; press '(', they can add a command that will be executed before the
;; command that is bound to '(', so that they can input the above
;; program in style below, without changing their key-pressing style:

;;     int main (int argc, char *argv[])
;;     {
;;             printf ("hello,world\n");
;;             return 0;
;;     }

;; With some extra tunings, they can input programs in gnu style with
;; bsd key-pressing style.

;; To tune with Casi, just execute M-x customize-variable RET
;; casi-per-style-preferences RET.  In the customization window, you
;; can set preferences for many styles.  If you devide configuration
;; for a style into several parts, only the first part will take
;; effect.

;; For each style, you can set "Fine tuning function", which must be a
;; function without any arguments, to tune settings after invoking
;; `c-set-style'.  When Casi mode is turned on, `c-set-style' will be
;; advised to invoke this function for the style you input.  When no
;; buffers turn Casi mode on, the advice will be disabled.

;; You can also set a series of key sequences and their associated
;; commands.  The key sequence is in the format of the argument of
;; `kbd'.  There are two commands for a key sequence: a before command
;; that will be executed before the orignal command for the key
;; sequence and an after command that after.  Both before commands and
;; after commands must be commands without any arguments, or with
;; exact one optional argument as prefix argument.  In a determined
;; style, when Casi mode is turned on and you type the set key
;; sequence, the before command for the key sequence and the style, if
;; exists, will be executed.  Then the orignal command.  Then the
;; after command if exists.  Prefix argument, if exists, will be
;; passed to all executed commands.  In the above example, if you give
;; the command that inserts a space in some cases the name
;; `my-insert-SPC-before-left-paren' and set it as the before command
;; for '(' for style "gnu", a space will be inserted before a '(' is
;; inserted in gnu style if Casi mode is on.

;; Both before and after command for a key sequence can absent.
;; Similar as the case of styles, if there are multiple entries for a
;; key sequence, only the first one will take effect.

;; Since Casi mode will modify key bindings of set key sequences, you
;; may not alter bindings for such key sequences after Casi mode is
;; on.  For the same reason, do not write "casi-mode: t" as file
;; variables, since it will not work.  If you want Casi mode to be
;; turned on automatically, add it to hooks such as
;; `c-mode-common-hook'.

;; Finally, you can use the command `casi-erase-blanks' to delete all
;; trivial blank characters at the end of each line.

;;; Code:
(require 'advice)
(require 'cc-mode)
(require 'cl)

(defvar casi-mode nil
  "Non-nil if Casi mode is enabled.
Use the command `casi-mode' to change this variable.")
(make-variable-buffer-local 'casi-mode)
(add-to-list 'minor-mode-alist '(casi-mode " Casi"))

;;;###autoload
(defun casi-mode (&optional arg)
  "Toggle C-like Automatic Style Input minor mode.
With no argument, this command toggles the mode.
Non-null prefix argument turns on the mode.
Null prefix argument turns off the mode.

Can be turned on only for CC modes or modes derived from CC
mode."
  (interactive (list (or current-prefix-arg
			 'toggle)))
  (if (or (not arg)
	  (and (not (eq arg 'toggle))
	       (< (prefix-numeric-value arg) 0))
	  (and casi-mode
	       (eq arg 'toggle)))
      (progn (turn-casi-mode-off)
	     (setq casi-mode nil)
	     (run-hooks 'casi-mode-hook
			'casi-mode-off-hook))
    (if c-buffer-is-cc-mode
	(progn (turn-casi-mode-on)
	       (setq casi-mode t)
	       (run-hooks 'casi-mode-hook
			  'casi-mode-on-hook))
      (error "Cannot turn on Casi mode for non-CC modes.")))
  ;; This ugly condition is for supporting Emacs 21.
  (if (not (and (functionp 'called-interactively-p)
		(not (called-interactively-p))))
      (message "Casi mode %sabled"
	       (if casi-mode
		   "en"
		 "dis")))
  (force-mode-line-update))

(defun casi-kill-buffer-hook ()
  "Discard Casi info about a file when a buffer is killed."
  (if casi-mode
      (turn-casi-mode-off)))
(add-hook 'kill-buffer-hook 'casi-kill-buffer-hook)

(defvar casi-style nil
  "Current Casi style in using.")
(make-variable-buffer-local 'casi-style)

(defun turn-casi-mode-on ()
  "Turn Casi mode on with `update-casi-mode', but will not set
`casi-mode' and run hooks."
  (update-casi-mode)
  (casi-add-current-buffer))

(defun turn-casi-mode-off ()
  "Turn Casi mode off, set `casi-style' to nil, but will not set
`casi-mode' and run hooks."
  (setq casi-style nil)
  (unload-casi-mode)
  (casi-remove-current-buffer))

(defvar casi-mode-on-buffers '()
  "Buffers that have turned Casi mode on.")

(defun casi-add-current-buffer ()
  "Add the current buffer to `casi-mode-on-buffers' and enable
advice for `c-set-style'."
  (let ((bufname (buffer-name)))
    (if (not (member-if (lambda (name)
			  (string= name bufname))
			casi-mode-on-buffers))
	(setq casi-mode-on-buffers
	      (cons bufname
		    casi-mode-on-buffers))))
  (ad-enable-advice 'c-set-style
		    'after
		    'change-casi-style-as-needed)
  (ad-activate 'c-set-style))

(defun casi-remove-current-buffer ()
  "Remove current buffer from `casi-mode-on-buffers'.  If there
is no such buffers, disable advice for `c-set-style'."
  (let ((bufname (buffer-name))
	(rest-buffers '()))
    (dolist (name casi-mode-on-buffers)
      (if (not (string= name bufname))
	  (setq rest-buffers (cons name rest-buffers))))
    (setq casi-mode-on-buffers rest-buffers))
  (if (null casi-mode-on-buffers)
      (progn (ad-disable-advice 'c-set-style
				'after
				'change-casi-style-as-needed)
	     (ad-activate 'c-set-style))))

(defadvice c-set-style (after change-casi-style-as-needed)
  "After invoking `c-set-style', change `casi-style' as needed."
  (if casi-mode
      (change-casi-style-if-necessary)))

(defun change-casi-style-if-necessary ()
  "Change `casi-style', invoke `update-casi-mode', when necessary.

Must be invoked when `casi-mode' is t."
  (if (or (null casi-style)
	  (not (string= casi-style
			c-indentation-style)))
      (update-casi-mode)))

(defun update-casi-mode ()
  "Unload and reload Casi mode."
  (unload-casi-mode)
  (setq casi-style c-indentation-style)
  (load-casi-mode casi-style))

(defgroup casi nil
  "C-like Automatic Style Input."
  :group 'c)

(defcustom casi-per-style-preferences
  '()
  "List of per-style preferences.

Preference of each style contains a fune tuning function and a
list of key-sequence-command pairs.

The fine tuning function will be invoked right after the style is
set.  It must be a function without any arguments.

Each key-sequence-command pair consists of two elements: a key
sequence, and a cons cell of two commands.  The key sequence is
in the format of the argument of `kbd'.  The two commands are the
before command that will be executed before orignal command for
the key sequence and the after command that after.  Both before
commands and after commands must be commands without any
arguments, or with exact one optional argument as prefix
argument.  When the commands are executed, if prefix argument
exists, it will be passed to them.  One or two of them for a key
sequence may absent."
  :type
  '(repeat
    (list
     :format "%v"
     (string :tag "Style")
     (set
      :doc "Function that will be invoked after `c-set-style'"
      :format "%v                %h"
      (function
       :tag "Fine tuning function"))
     (repeat
      :tag "Key sequences and commands"
      (cons
       :format "%v%v"
       (string
	:doc "In the format of the argument of `kbd', e.g. <f7>"
	:format "%t: %v                        %h"
	:tag "Key sequence string")
       (cons
	:format "%v"
	(set
	 :doc "Command executed before the orignal command"
	 :format "%v                            %h"
	 (function
	  :tag "Before command"))
	(set :doc "Command executed after the orignal command"
	     :format "%v                            %h"
	     (function
	      :tag "After command")))))))
  :group 'casi)

(defmacro casi-retrieve-associated-info (style func)
  (let ((entry (make-symbol "--entry--")))
    `(let ((,entry
	    (assoc ,style casi-per-style-preferences)))
       (funcall ,func ,entry))))

(defmacro casi-user-fine-tuning-func (style)
  `(casi-retrieve-associated-info ,style
				  (lambda (l)
				    (car-safe
				     (car-safe
				      (cdr-safe l))))))

(defmacro casi-user-preferences (style)
  `(casi-retrieve-associated-info ,style
				  (lambda (l)
				    (car-safe
				     (cdr-safe
				      (cdr-safe l))))))

(defmacro casi-preference-key (preference)
  ;; `kbd' does not work here, so use more primtive `read-kbd-macro'.
  ;; Unfortunately, `read-kbd-macro' cannot handle blank-only strings
  ;; well, so we have to handle them ourselves.  But we only handle
  ;; the cases of a single space and a single horizontal tab.  If
  ;; other cases need to be handled, this macro has to be adjusted.
  (let ((key (make-symbol "--key--")))
    `(let ((,key (car ,preference)))
       (cond ((string= " " ,key)
	      [32])
	     ((string= "\t" ,key)
	      [9])
	     (t
	      (read-kbd-macro ,key t))))))

(defmacro casi-preference-command (preference)
  `(cdr ,preference))

(defmacro casi-make-record-query (key)
  "Create a record query for KEY."
  `(list (buffer-name) major-mode casi-style ,key))

(defmacro casi-record-query-bufname (query)
  `(car ,query))

(defmacro casi-record-query-mode (query)
  `(cadr ,query))

(defmacro casi-record-query-style (query)
  `(caddr ,query))

(defmacro casi-record-query-key (query)
  `(cadddr ,query))

(defun load-casi-mode (style)
  "Load Casi mode for STYLE.  Will update key binding preferences
and fine tune settings."
  ;; Update key bindings for this buffer
  (let ((preferences (casi-user-preferences style)))
    (dolist (prefer preferences)
      (let ((key (casi-preference-key prefer))
	    (new-command (casi-preference-command
			  prefer)))
	(save-default-key-binding! key)
	(record-and-set-key! key new-command))))
  ;; Fine tune settings.
  (let ((func (casi-user-fine-tuning-func style)))
    (if func
	(funcall func))))

(defun unload-casi-mode ()
  "Unload Casi mode.  The default key bindings will be
recovered."
  (recover-default-key-bindings))

(defmacro casi-conditional-execute (key &rest body)
  "Execute forms in BODY only when KEY is not bound to
`casi-execute-binding-for'.
The value returned is the value of the last form in BODY."
  `(if (not (eq (local-key-binding ,key)
		'casi-execute-binding-for))
       (progn ,@body)))

(defmacro mode-map-symbol (mode)
  `(intern (concat (symbol-name ,mode) "-map")))

(defmacro mode-map (mode)
  `(symbol-value (mode-map-symbol ,mode)))

(defmacro mode-map-exists? (mode)
  `(boundp (mode-map-symbol ,mode)))

(defmacro recover-binding-for (key mode)
  "Recover keybinding for KEY for MODE."
  (let ((query (make-symbol "--query--")))
    `(if (mode-map-exists? ,mode)
	 (let ((,query (cons ,mode ,key)))
	   (define-key (mode-map ,mode)
	     ,key
	     (cdr-safe (assoc ,query
			      casi-default-key-bindings)))))))

(defvar casi-default-key-bindings '()
  "List that saves orignal key bindings for a mode.

The key is a cons cell (MAJOR-MODE . KEY), and the value is a
command.")

(defun save-default-key-binding! (key)
  "Save orignal key bindings of KEY for a major mode."
  (casi-conditional-execute
   key
   (let ((query (cons major-mode key)))
     (let ((binding (assoc query
			   casi-default-key-bindings)))
       (if binding
	   (setcdr binding
		   (local-key-binding key))
	 (setq casi-default-key-bindings
	       (cons (cons query
			   (local-key-binding key))
		     casi-default-key-bindings)))))))

(defvar casi-recorded-key-bindings '()
  "List that saves user prefered key bindings.

The key is a list (BUFFER-NAME MAJOR-MODE STYLE KEY), and the
value is the before and after command for KEY.")

(defun record-and-set-key! (key command)
  "Record COMMAND as user prefered for KEY for the current
buffer.

Binding of KEY in all buffers in the mode that the current buffer
is in will be changed into `casi-execute-binding-for', but the
final command executed when the user type KEY will be COMMAND in
buffers that turn Casi mode on and the orignal command in buffers
that do not turn Casi mode on.

COMMAND may be one command or two commands, i.e. a before command
and/or an after command.  See `casi-execute-binding-for' for more
information about how these commands are executed."
  (let ((query (casi-make-record-query key)))
    (let ((binding (assoc query
			  casi-recorded-key-bindings)))
      (if binding
	  (setcdr binding command)
	(setq casi-recorded-key-bindings
	      (cons (cons query command)
		    casi-recorded-key-bindings)))))
  (casi-conditional-execute
   key
   (local-set-key key 'casi-execute-binding-for)))

(defun recover-default-key-bindings ()
  "Recover orignal key bindings for the current buffer."
  (let ((new-recorded-bindings '())
	(name (buffer-name)))
    (dolist (binding casi-recorded-key-bindings)
      (let* ((query (car binding))
	     (qkey (casi-record-query-key query))
	     (qmode (casi-record-query-mode query)))
	(if (string= (casi-record-query-bufname query) name)
	    (if (and (not (more-such-bindings-exist? qkey
						     qmode))
		     (mode-map-exists? qmode)
		     (eq (lookup-key (mode-map qmode) qkey)
			 'casi-execute-binding-for))
		(recover-binding-for qkey qmode))
	  (setq new-recorded-bindings
		(cons binding new-recorded-bindings)))))
    (setq casi-recorded-key-bindings new-recorded-bindings)))

(defun more-such-bindings-exist? (key mode)
  "Return t if bindings of KEY for MODE in other buffers exist.
Otherwise, return nil."
  (let ((name (buffer-name)))
    (catch 'found-bindings?
      (dolist (binding casi-recorded-key-bindings)
	(let* ((query (car binding))
	       (qname (casi-record-query-bufname query))
	       (qmode (casi-record-query-mode query))
	       (qkey (casi-record-query-key query)))
	  (if (and (not (string= qname name))
		   (eq qmode mode)
		   (equal qkey key))
	      (throw 'found-bindings? t)))))))

(defmacro casi-local-command (key)
  "Commands for KEY in the current buffer."
  `(if casi-mode
       (progn (change-casi-style-if-necessary)
	      (cdr-safe (assoc (casi-make-record-query ,key)
			       casi-recorded-key-bindings)))
     nil))

;; The macros `casi-local-before-command' and
;; `casi-local-after-command' are relative to the details of
;; `casi-per-style-preferences' but they are put here because they are
;; more relative to `casi-execute-binding-for'.
(defmacro casi-local-before-command (key)
  "Before command for KEY in the current buffer."
  `(car-safe (car-safe (casi-local-command ,key))))

(defmacro casi-local-after-command (key)
  "After command for KEY in the current buffer."
  `(car-safe (cdr-safe (casi-local-command ,key))))

(defmacro casi-default-command (key)
  "Command for KEY if there is no Casi mode in the current
buffer."
  `(cdr-safe (assoc (cons major-mode ,key)
		    casi-default-key-bindings)))

(defmacro casi-global-command (key)
  "Command for KEY in global map."
  `(global-key-binding ,key))

(defmacro with-prefix-arg (arg &rest body)
  "Execute the forms in BODY with ARG as prefix argument temporarily.
The value returned is the value of `prefix-arg' before invoking
this macro."
  (let ((old-arg (make-symbol "--old-arg--")))
    `(let ((,old-arg prefix-arg))
       (setq prefix-arg ,arg)
       ,@body
       (setq prefix-arg ,old-arg))))

(defun casi-execute-binding-for (&optional arg)
  "Execute binding for the last typed key sequence.

Commands will be executed in the following order:

1. If the before command for the key sequence exists, execute it.

2. If the orignal buffer local command for the key sequence
   exists, execute it.

3. If the local command in step 2 is not executed, execute the
   global command of the key sequence.

4. If the after command for the key sequence exists, execute it.

The optional ARG will be passed to all commands above as prefix
argument."
  (interactive (list (or current-prefix-arg
			 'nil)))
  (let* ((key (this-single-command-keys))
	 (bcmd (casi-local-before-command key))
	 (acmd (casi-local-after-command key))
	 (dcmd (casi-default-command key))
	 (gcmd (casi-global-command key)))
    (with-prefix-arg arg
		     (if bcmd
			 (command-execute bcmd)))
    (with-prefix-arg arg
		     (if dcmd
			 (command-execute dcmd)
		       (if gcmd
			   (command-execute gcmd))))
    (with-prefix-arg arg
		     (if acmd
			 (command-execute acmd)))))

(defun casi-erase-blanks ()
  "Erase all trivial blanks for Casi mode."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "[ \t]+$" nil t)
      (replace-match "" nil nil))))

(provide 'casi)

;;; casi.el ends here
