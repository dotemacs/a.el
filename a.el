;;; a.el --- Associative function              -*- lexical-binding: t; -*-

;; Copyright (C) 2017  Arne Brasseur

;; Author: Arne Brasseur <arne@arnebrasseur.net>
;; Package-Requires: ((dash "") (emacs "25"))

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the Mozilla Public License Version 2.0

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
;; details.

;; You should have received a copy of the Mozilla Public License along with this
;; program. If not, see <https://www.mozilla.org/media/MPL/2.0/index.txt>.

;;; Commentary:

;; Library for dealing with associative data structures: alists, hash-maps, and
;; vectors (for vectors, the indices are treated as keys)

;;; Code:

(require 'dash)


(defun a-get (map key &optional not-found)
  "Returns the value mapped to key, not-found or nil if key not present."
  (cond
   ((listp map)         (alist-get key map not-found))
   ((vectorp map)       (if (a-has-key? map key)
                            (aref map key)
                          not-found))
   ((hash-table-p map)  (gethash key map not-found))
   (t (user-error "Not associative: %S" map))))

(defun a-get-in (m ks &optional not-found)
  "Returns the value in a nested associative structure, where ks is a sequence of keys. Returns nil if the key is not present, or the not-found value if supplied."
  (let ((result m))
    (cl-block nil
      (seq-doseq (k ks)
        (if (a-has-key? result k)
            (setq result (a-get result k))
          (cl-return not-found)))
      result)))

(defun a-has-key? (coll k)
  "Checks if the given associative collection contains a certain key. Like Clojure's `contains?', but more aptly named."
  (cond
   ((listp coll)         (not (eq (alist-get k coll :not-found) :not-found)))
   ((vectorp coll)       (and (integerp k) (< -1 k (length coll))))
   ((hash-table-p coll)  (not (eq (gethash k coll :not-found) :not-found)))
   (t (user-error "Not associative: %S" coll))))

(defun a-assoc-1 (coll k v)
  "Like a-assoc, but only takes a single k-v pair. Internal helper function."
  (cond
   ((listp coll)
    (if (a-has-key? coll k)
        (mapcar (lambda (entry)
                  (if (equal (car entry) k)
                      (cons k v)
                    entry))
                coll)
      (cons (cons k v) coll)))

   ((vectorp coll)
    (if (and (integerp k) (> k 0))
        (if (< k (length coll))
            (let ((copy (copy-sequence coll)))
              (aset copy k v)
              copy)
          (vconcat coll (-repeat (- k (length coll)) nil) (list v)))))

   ((vectorp coll)
    (if (and (integerp k) (> k 0))
        (if (< k (length coll))
            (let ((copy (copy-sequence coll)))
              (aset copy k v)
              copy)
          (vconcat coll (-repeat (- k (length coll)) nil) (list v)))))))

(defun a-assoc (coll &rest kvs)
  "Return an updated collection, associating values with keys."
  (-reduce-from (lambda (coll kv)
                  (seq-let [k v] kv
                    (a-assoc-1 coll k v)))
                coll (-partition 2 kvs)))

(defun a-keys (coll)
  "Return the keys in the collection"
  (cond
   ((listp coll)
    (mapcar #'car coll))

   ((hash-table-p coll)
    (let ((acc nil))
      (maphash (lambda (k _) (push k acc)) coll)
      acc))))

(defun a-vals (coll)
  "Return the values in the collection"
  (cond
   ((listp coll)
    (mapcar #'cdr coll))

   ((hash-table-p coll)
    (let ((acc nil))
      (maphash (lambda (_ v) (push v acc)) coll)
      acc))))

(defun a-reduce-kv (fn from coll)
  "Reduce an associative collection, starting with an initial value of FROM. The reducing functions receives the intermediate value, key, and value."
  (-reduce-from (lambda (acc key)
                  (funcall fn acc key (a-get coll key)))
                from (a-keys coll)))

(defun a-count (coll)
  "Like length, but can also return the length of hash tables."
  (cond
   ((seqp coll)
    (length coll))

   ((hash-table-p coll)
    (length (a-keys coll)))))

(defun a-equal (a b)
  "Reduce an associative collection, starting with an initial value of FROM. The reducing functions receives the intermediate value, key, and value."
  (and (eq (a-count a) (a-count b))
       (a-reduce-kv (lambda (bool k v)
                      (and bool (equal v (a-get b k))))
                    t
                    a)))

(defun a-merge (&rest colls)
  "Merge multiple associative collections. Returns the type of the first collection."
  (-reduce (lambda (this that)
             (a-reduce-kv (lambda (coll k v)
                            (a-assoc coll k v))
                          this
                          that))
           colls))

(defun a-alist (&rest kvs)
  "Create an association list from the given keys and values, provided as a single list of arguments. e.g. (a-alist :foo 123 :bar 456)"
  (mapcar (lambda (kv) (cons (car kv) (cadr kv))) (-partition 2 kvs)))

(defun a-assoc-in (coll keys value)
  "Associates a value in a nested associative structure, where ks is a sequence of keys and v is the new value and returns a new nested structure. If any levels do not exist, association lists will be created."
  (case (length keys)
    (0 coll)
    (1 (a-assoc-1 coll (elt keys 0) value))
    (t (a-assoc-1 coll
                (elt keys 0)
                (a-assoc-in (a-get coll (elt keys 0))
                            (seq-drop keys 1)
                            value)))))

(defun a-update (coll key fn &rest args)
  "'Updates' a value in an associative structure, where key is a key and fn is a function that will take the old value and any supplied args and return the new value, and returns a new structure.  If the key does not exist, nil is passed as the old value."
  (a-assoc-1 coll
             key
             (apply #'funcall fn (a-get coll key) args)))

(defun a-update-in (coll keys fn &rest args)
  "'Updates' a value in a nested associative structure, where `keys' is a sequence of keys and fn is a function that will take the old value and any supplied args and return the new value, and returns a new nested structure.  If any levels do not exist, association lists will be created."
  (case (length keys)
    (0 coll)
    (1 (apply #'a-update coll (elt keys 0) fn args))
    (t (a-assoc-1 coll
                (elt keys 0)
                (apply #'a-update-in
                       (a-get coll (elt keys 0))
                       (seq-drop keys 1)
                       fn
                       args)))))

(provide 'a)
;;; a.el ends here
