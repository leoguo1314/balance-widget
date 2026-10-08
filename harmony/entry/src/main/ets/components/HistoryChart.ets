import { Snapshot } from '../core/Core';

@Component
export struct HistoryChart {
  @Prop @Watch('redraw') points: Snapshot[] = [];
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private w: number = 300;
  private h: number = 180;
  private ready: boolean = false;

  redraw(): void {
    if (!this.ready) return;
    const ctx: CanvasRenderingContext2D = this.context;
    ctx.clearRect(0, 0, this.w, this.h);
    if (this.points.length === 0) return;
    const values: number[] = this.points.map((p: Snapshot) => p.value);
    const low: number = Math.min(...values); const high: number = Math.max(...values);
    const span: number = Math.max(high - low, 1);
    const first: number = this.points[0].timestamp;
    const duration: number = Math.max(1, this.points[this.points.length - 1].timestamp - first);
    ctx.strokeStyle = '#DFE6F0'; ctx.lineWidth = 1;
    for (let i: number = 0; i < 4; i++) {
      const y: number = 25 + (this.h - 50) * i / 3;
      ctx.beginPath(); ctx.moveTo(20, y); ctx.lineTo(this.w - 20, y); ctx.stroke();
    }
    ctx.strokeStyle = '#3469D6'; ctx.lineWidth = 2.5; ctx.beginPath();
    this.points.forEach((p: Snapshot, i: number) => {
      const x: number = 20 + (p.timestamp - first) / duration * (this.w - 40);
      const y: number = this.h - 25 - (p.value - low) / span * (this.h - 50);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    });
    ctx.stroke();
    ctx.fillStyle = '#6E7D93'; ctx.font = '11vp sans-serif';
    ctx.fillText('最高 ' + high.toFixed(2), 20, 14);
    ctx.fillText('最低 ' + low.toFixed(2), 20, this.h - 6);
    const last: Snapshot = this.points[this.points.length - 1];
    const x: number = 20 + (last.timestamp - first) / duration * (this.w - 40);
    const y: number = this.h - 25 - (last.value - low) / span * (this.h - 50);
    ctx.fillStyle = '#3469D6'; ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill();
  }

  build() {
    Canvas(this.context).width('100%').height(180)
      .onReady(() => { this.ready = true; this.redraw(); })
      .onAreaChange((_, area) => { this.w = Number(area.width); this.h = Number(area.height); this.redraw(); })
  }
}
