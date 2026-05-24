using Godot;
using Godot.Collections;

public partial class PlayerPointClick : CharacterBody2D
{
    [ExportCategory("Point-Click Properties")]
    [Export] public float MoveSpeed { get; set; } = 250.0f;
    [Export] public float StopThreshold { get; set; } = 1.0f;
    [Export] public NodePath BoundaryPath { get; set; }

    private Vector2 targetPosition;
    private bool isMoving;
    private Vector2[] boundaryPolygon = [];

    private AnimatedSprite2D playerSprite;
    private CpuParticles2D particleTrails;

    public override void _Ready()
    {
        targetPosition = GlobalPosition;
        playerSprite = GetNode<AnimatedSprite2D>("AnimatedSprite2D");
        particleTrails = GetNodeOrNull<CpuParticles2D>("ParticleTrails");

        if (BoundaryPath != null)
        {
            var boundaryNode = GetNode<CollisionPolygon2D>(BoundaryPath);
            var poly = boundaryNode.Polygon;
            var offset = boundaryNode.GlobalPosition;
            boundaryPolygon = new Vector2[poly.Length];
            for (int i = 0; i < poly.Length; i++)
                boundaryPolygon[i] = poly[i] + offset;
        }
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouseBtn
            && mouseBtn.ButtonIndex == MouseButton.Left
            && mouseBtn.Pressed)
        {
            var clickPos = GetGlobalMousePosition();
            if (boundaryPolygon.Length > 0)
                clickPos = ClampToBoundary(clickPos);
            targetPosition = clickPos;
            isMoving = true;
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        Movement();
        PlayerAnimations();
        FlipPlayer();
    }

    private void Movement()
    {
        if (!isMoving)
        {
            Velocity = Vector2.Zero;
            return;
        }

        var direction = (targetPosition - GlobalPosition).Normalized();
        var distance = GlobalPosition.DistanceTo(targetPosition);

        if (distance < StopThreshold)
        {
            Velocity = Vector2.Zero;
            GlobalPosition = targetPosition;
            isMoving = false;
        }
        else
        {
            Velocity = direction * MoveSpeed;
            isMoving = true;
        }

        MoveAndSlide();

        if (boundaryPolygon.Length > 0)
            GlobalPosition = ClampToBoundary(GlobalPosition);
    }

    private Vector2 ClampToBoundary(Vector2 pos)
    {
        if (Geometry2D.IsPointInPolygon(pos, boundaryPolygon))
            return pos;

        var closest = boundaryPolygon[0];
        var minDist = pos.DistanceSquaredTo(closest);

        for (int i = 1; i < boundaryPolygon.Length; i++)
        {
            var segEnd = boundaryPolygon[i];
            var segStart = boundaryPolygon[i - 1];
            var nearest = Geometry2D.GetClosestPointToSegment(pos, segStart, segEnd);
            var d = pos.DistanceSquaredTo(nearest);
            if (d < minDist)
            {
                minDist = d;
                closest = nearest;
            }
        }
        return closest;
    }

    private void PlayerAnimations()
    {
        if (particleTrails != null)
            particleTrails.Emitting = false;

        if (isMoving)
        {
            if (particleTrails != null)
                particleTrails.Emitting = true;
            playerSprite.Play("Walk", 1.5f);
        }
        else
        {
            playerSprite.Play("Idle");
        }
    }

    private void FlipPlayer()
    {
        if (Velocity.X < -1.0f)
            playerSprite.FlipH = true;
        else if (Velocity.X > 1.0f)
            playerSprite.FlipH = false;
    }
}
