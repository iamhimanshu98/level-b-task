-- 1. InsertOrderDetails
CREATE PROCEDURE InsertOrderDetails
    @OrderID INT,
    @ProductID INT,
    @UnitPrice MONEY = NULL,
    @Quantity INT,
    @Discount FLOAT = 0,
    @LocationID SMALLINT = 50
AS
BEGIN
    DECLARE @ActualUnitPrice MONEY;
    DECLARE @CurrentStock INT;
    DECLARE @ReorderLevel INT;

    -- Determine actual unit price
    SET @ActualUnitPrice = ISNULL(@UnitPrice, (SELECT ListPrice FROM Production.Product WHERE ProductID = @ProductID));

    -- Get current stock
    SELECT @CurrentStock = Quantity
    FROM Production.ProductInventory
    WHERE ProductID = @ProductID AND LocationID = @LocationID;

    -- Get reorder level
    SELECT TOP 1 @ReorderLevel = MinimumOrderQty
    FROM Purchasing.ProductVendor
    WHERE ProductID = @ProductID
    ORDER BY AverageLeadTime ASC;

    -- Handle missing product/inventory data
    IF @CurrentStock IS NULL
    BEGIN
        PRINT 'Error: Product inventory information not found for the given ProductID at the specified location.';
        RETURN;
    END

    -- Handle insufficient stock
    IF @CurrentStock < @Quantity
    BEGIN
        PRINT 'Error: Not enough stock available. Order not inserted.';
        RETURN;
    END

    -- Insert order detail
    INSERT INTO Sales.SalesOrderDetail (SalesOrderID, ProductID, UnitPrice, OrderQty, UnitPriceDiscount)
    VALUES (@OrderID, @ProductID, @ActualUnitPrice, @Quantity, @Discount);

    -- Check if insert failed
    IF @@ROWCOUNT = 0
    BEGIN
        PRINT 'Error: Failed to place the order. Please try again.';
        RETURN;
    END

    -- Update stock
    UPDATE Production.ProductInventory
    SET Quantity = Quantity - @Quantity
    WHERE ProductID = @ProductID AND LocationID = @LocationID;

    -- Check for reorder warning (only if reorder level was found)
    IF @ReorderLevel IS NOT NULL AND EXISTS (
        SELECT 1
        FROM Production.ProductInventory
        WHERE ProductID = @ProductID
          AND LocationID = @LocationID
          AND Quantity < @ReorderLevel
    )
    BEGIN
        PRINT 'Warning: Stock below reorder level.';
    END
END;


-- 2. UpdateOrderDetails
GO
CREATE PROCEDURE UpdateOrderDetails
    @OrderID INT,
    @ProductID INT,
    @UnitPrice MONEY = NULL,
    @Quantity INT = NULL,
    @Discount FLOAT = NULL
AS
BEGIN
    UPDATE Sales.SalesOrderDetail
    SET 
        UnitPrice = ISNULL(@UnitPrice, UnitPrice),
        OrderQty = ISNULL(@Quantity, OrderQty),
        UnitPriceDiscount = ISNULL(@Discount, UnitPriceDiscount)
    WHERE SalesOrderID = @OrderID AND ProductID = @ProductID;
END;


-- 3. GetOrderDetails
GO
CREATE PROCEDURE GetOrderDetails
    @OrderID INT
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Sales.SalesOrderDetail WHERE SalesOrderID = @OrderID)
    BEGIN
        PRINT 'The OrderID ' + CAST(@OrderID AS VARCHAR) + ' does not exist';
        RETURN 1;
    END

    SELECT * FROM Sales.SalesOrderDetail WHERE SalesOrderID = @OrderID;
END;


-- 4. DeleteOrderDetails
GO
CREATE PROCEDURE DeleteOrderDetails
    @OrderID INT,
    @ProductID INT
AS
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM Sales.SalesOrderDetail 
        WHERE SalesOrderID = @OrderID AND ProductID = @ProductID
    )
    BEGIN
        PRINT 'Invalid OrderID or ProductID';
        RETURN -1;
    END

    DELETE FROM Sales.SalesOrderDetail 
    WHERE SalesOrderID = @OrderID AND ProductID = @ProductID;
END;



-- Functions
-- 1. Format as MM/DD/YYYY
GO
CREATE FUNCTION FormatDate_MMDDYYYY (@inputDate DATETIME)
RETURNS VARCHAR(10)
AS
BEGIN
    RETURN CONVERT(VARCHAR(10), @inputDate, 101)
END;


-- 2. Format as YYYYMMDD
GO
CREATE FUNCTION FormatDate_YYYYMMDD (@inputDate DATETIME)
RETURNS VARCHAR(8)
AS
BEGIN
    RETURN CONVERT(VARCHAR(8), @inputDate, 112)
END;


-- views
-- 1. vwCustomerOrders
GO

CREATE VIEW vwCustomerOrders AS
SELECT
    CASE
        WHEN s.Name IS NOT NULL THEN s.Name
        WHEN p.FirstName IS NOT NULL THEN p.FirstName + ' ' + p.LastName
        ELSE 'Unknown Customer'
    END AS CustomerName,
    o.SalesOrderID AS OrderID,
    o.OrderDate,
    od.ProductID,
    pr.Name AS ProductName,
    od.OrderQty AS Quantity,
    od.UnitPrice,
    od.OrderQty * od.UnitPrice AS Total
FROM Sales.Customer c
JOIN Sales.SalesOrderHeader o ON c.CustomerID = o.CustomerID
JOIN Sales.SalesOrderDetail od ON o.SalesOrderID = od.SalesOrderID
JOIN Production.Product pr ON od.ProductID = pr.ProductID
LEFT JOIN Sales.Store s ON c.StoreID = s.BusinessEntityID
LEFT JOIN Person.Person p ON c.PersonID = p.BusinessEntityID;

-- 2. Yesterday’s Orders
GO
CREATE VIEW vwCustomerOrders_Yesterday AS
SELECT * FROM vwCustomerOrders
WHERE OrderDate = CAST(GETDATE() - 1 AS DATE);

-- 3. MyProducts
GO
CREATE VIEW MyProducts AS
SELECT 
    p.ProductID,
    p.Name AS ProductName,
    p.StandardCost AS QuantityPerUnit,
    p.ListPrice AS UnitPrice,
    s.Name AS CompanyName,
    c.Name AS CategoryName
FROM Production.Product p
JOIN Production.ProductSubcategory ps ON p.ProductSubcategoryID = ps.ProductSubcategoryID
JOIN Production.ProductCategory c ON ps.ProductCategoryID = c.ProductCategoryID
JOIN Purchasing.ProductVendor pv ON p.ProductID = pv.ProductID
JOIN Purchasing.Vendor s ON pv.BusinessEntityID = s.BusinessEntityID
WHERE p.DiscontinuedDate IS NULL;


-- triggers
-- 1. INSTEAD OF DELETE on Orders
GO
CREATE TRIGGER trg_DeleteOrder
ON Sales.SalesOrderHeader
INSTEAD OF DELETE
AS
BEGIN
    DELETE FROM Sales.SalesOrderDetail
    WHERE SalesOrderID IN (SELECT SalesOrderID FROM DELETED);

    DELETE FROM Sales.SalesOrderHeader
    WHERE SalesOrderID IN (SELECT SalesOrderID FROM DELETED);
END;


-- 2. Check Stock BEFORE Inserting Order
GO
CREATE TRIGGER trg_InsertOrderDetail_CheckStock
ON Sales.SalesOrderDetail
INSTEAD OF INSERT
AS
BEGIN
    DECLARE @ProductID INT;
    DECLARE @OrderQty INT;
    DECLARE @SalesOrderID INT;
    DECLARE @UnitPrice MONEY;
    DECLARE @UnitPriceDiscount MONEY;
    DECLARE @LocationID SMALLINT = 50;

    SELECT TOP 1
        @SalesOrderID = i.SalesOrderID,
        @ProductID = i.ProductID,
        @OrderQty = i.OrderQty,
        @UnitPrice = i.UnitPrice,
        @UnitPriceDiscount = i.UnitPriceDiscount
    FROM INSERTED AS i;

    DECLARE @CurrentStock INT;

    SELECT @CurrentStock = Quantity
    FROM Production.ProductInventory
    WHERE ProductID = @ProductID AND LocationID = @LocationID;

    IF @CurrentStock IS NULL
    BEGIN
        PRINT 'Error: Inventory information not found for ProductID ' + CAST(@ProductID AS NVARCHAR(10)) + ' at LocationID ' + CAST(@LocationID AS NVARCHAR(10)) + '. Order could not be placed.';
        RETURN;
    END

    IF @CurrentStock < @OrderQty
    BEGIN
        PRINT 'Error: Insufficient stock for ProductID ' + CAST(@ProductID AS NVARCHAR(10)) + '. Available: ' + CAST(@CurrentStock AS NVARCHAR(10)) + ', Requested: ' + CAST(@OrderQty AS NVARCHAR(10)) + '. Order could not be placed.';
        RETURN;
    END

    BEGIN
        INSERT INTO Sales.SalesOrderDetail (SalesOrderID, OrderQty, ProductID, UnitPrice, UnitPriceDiscount)
        SELECT SalesOrderID, OrderQty, ProductID, UnitPrice, UnitPriceDiscount
        FROM INSERTED;

        UPDATE pi
        SET Quantity = pi.Quantity - i.OrderQty
        FROM Production.ProductInventory AS pi
        INNER JOIN INSERTED AS i ON pi.ProductID = i.ProductID
        WHERE pi.LocationID = @LocationID;
    END
END;
