-- Base de datos y usuario para la aplicación (trabajo final CNVR)
CREATE DATABASE IF NOT EXISTS cnvr;

-- Usuario que solo puede conectarse desde la VLAN 10.1.100.0/24
CREATE USER IF NOT EXISTS 'cnvr'@'10.1.100.%' IDENTIFIED BY 'cnvr2627';
GRANT ALL PRIVILEGES ON cnvr.* TO 'cnvr'@'10.1.100.%';
FLUSH PRIVILEGES;

USE cnvr;
CREATE TABLE IF NOT EXISTS accesos (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  origen    VARCHAR(64) NOT NULL,
  mensaje   VARCHAR(255),
  fecha     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO accesos (origen, mensaje) VALUES ('bbdd', 'Base de datos inicializada por VNX');
