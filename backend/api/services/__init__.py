"""
Paquet des services métier de l'API SGSUS.

Contenu :
    * `conflicts` : règles de planification des soutenances (EXG01, F03…) ;
    * `sante`     : diagnostic de l'état du service pour la sonde /health/.

Les services contiennent la logique métier indépendante du transport HTTP :
ils sont appelés par les sérialiseurs et les vues, et testables isolément.
"""
