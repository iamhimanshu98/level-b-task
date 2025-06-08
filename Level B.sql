-- 1. Find the names of employees who live in a particular city (e.g., 'Seattle').
SELECT p.FirstName, p.LastName
FROM Person.Person p
JOIN HumanResources.Employee e ON p.BusinessEntityID = e.BusinessEntityID
JOIN Person.BusinessEntityAddress bea ON p.BusinessEntityID = bea.BusinessEntityID
JOIN Person.Address a ON bea.AddressID = a.AddressID
WHERE a.City = 'Seattle';

-- 2. List the total sales amount for each salesperson.
SELECT sp.BusinessEntityID, p.FirstName, p.LastName, SUM(soh.TotalDue) AS TotalSales
FROM Sales.SalesPerson sp
JOIN Sales.SalesOrderHeader soh ON sp.BusinessEntityID = soh.SalesPersonID
JOIN Person.Person p ON sp.BusinessEntityID = p.BusinessEntityID
GROUP BY sp.BusinessEntityID, p.FirstName, p.LastName;

-- 3. Display the details of the top 5 most expensive products.
SELECT TOP 5 Name, ProductNumber, ListPrice
FROM Production.Product
ORDER BY ListPrice DESC;

-- 4. List customers who have not placed any orders.
SELECT c.CustomerID, p.FirstName, p.LastName
FROM Sales.Customer c
JOIN Person.Person p ON c.PersonID = p.BusinessEntityID
LEFT JOIN Sales.SalesOrderHeader soh ON c.CustomerID = soh.CustomerID
WHERE soh.SalesOrderID IS NULL;

-- 5. Find the average, min, and max order total for each customer.
SELECT c.CustomerID, 
       p.FirstName, 
       p.LastName,
       AVG(soh.TotalDue) AS AvgOrderTotal,
       MIN(soh.TotalDue) AS MinOrderTotal,
       MAX(soh.TotalDue) AS MaxOrderTotal
FROM Sales.Customer c
JOIN Person.Person p ON c.PersonID = p.BusinessEntityID
JOIN Sales.SalesOrderHeader soh ON c.CustomerID = soh.CustomerID
GROUP BY c.CustomerID, p.FirstName, p.LastName;
